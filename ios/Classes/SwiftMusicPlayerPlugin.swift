import Flutter
import UIKit
import AVKit
import AVFoundation

import MediaPlayer


enum MusicPlayerError: Error {
  case unknownMethod
  case invalidUrl
}

@available(iOS 10.0, *)
public class SwiftMusicPlayerPlugin: NSObject, FlutterPlugin {
  /// How often the position of the player should be updated.
  let positionUpdateInterval = TimeInterval(0.1)
  
  
  let player: AVPlayer
  let channel: FlutterMethodChannel
  var positionTimer: Timer?
  // In ms
  var duration: Double?
  var position = 0.0
  
  var trackName = ""
  var albumName = ""
  var artistName = ""
  var image: UIImage?
  
  
  var itemStatusObserver: NSKeyValueObservation?
  var timeControlStatusObserver: NSKeyValueObservation?
  var durationObserver: NSKeyValueObservation?
  
  
  init(_ channel: FlutterMethodChannel) {
    self.player = AVPlayer()
    self.channel = channel
    super.init()
    timeControlStatusObserver = player.observe(\AVPlayer.timeControlStatus) { [unowned self] player, _ in
      self.timeControlStatusChanged(player.timeControlStatus)
    }
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget(handler: {
      (event) in
      if self.player.timeControlStatus == AVPlayer.TimeControlStatus.paused {
        self.resume()
      } else {
        self.pause()
      }
      return MPRemoteCommandHandlerStatus.success
    })
  }
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "exit.live/music_player", binaryMessenger: registrar.messenger())
    let instance = SwiftMusicPlayerPlugin(channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }
  
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    print("\(call.method)")
    do {
      switch call.method {
      case "play":
        try play(call.arguments as! NSDictionary)
      case "pause":
        pause()
      case "resume":
        resume()
      case "showCover":
        try showCover(call.arguments as! String)
      default:
        throw MusicPlayerError.unknownMethod
      }
      result("iOS " + UIDevice.current.systemVersion)
    } catch {
      print("MusicPlayer flutter bridge error: \(error)")
      result(0)
    }
  }
  
  
  func play(_ properties: NSDictionary) throws {
    let audioSession = AVAudioSession.sharedInstance()

    try audioSession.setCategory(AVAudioSessionCategoryPlayback, mode: AVAudioSessionModeDefault, options: [])
    try audioSession.setActive(true)

    // Resetting values.
    self.duration = nil
    position = 0.0
    // Since the positionTimer is only set when `readyToPlay` we reset it
    // immediately here.
    positionTimer?.invalidate()
    positionTimer = nil
    
    let urlString = properties["url"] as! String
    let url = URL.init(string: urlString)
    if url == nil {
      throw MusicPlayerError.invalidUrl
    }
    
    trackName = properties["trackName"] as! String
    albumName = properties["albumName"] as! String
    artistName = properties["artistName"] as! String
    
    print("URL: \(String(describing: url))")
    let playerItem = AVPlayerItem.init(url: url!)
    
    
    itemStatusObserver = playerItem.observe(\AVPlayerItem.status) { [unowned self] playerItem, _ in
      self.itemStatusChanged(playerItem.status)
    }
    
    durationObserver = playerItem.observe(\AVPlayerItem.duration) { [unowned self] playerItem, _ in
      self.durationChanged()
    }
    
    player.replaceCurrentItem(with: playerItem)
    player.play()
  }
  
  func showCover(_ fileName: String) throws {
    let documentsUrl =  FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    let imageUrl = documentsUrl.appendingPathComponent(fileName)
    let imageData = try Data.init(contentsOf: imageUrl)
    image = UIImage.init(data: imageData)
    updateInfoCenter()
  }
  
  func updateInfoCenter() {
    var songInfo = [String : Any]()
    songInfo[MPNowPlayingInfoPropertyPlaybackRate] = player.timeControlStatus == AVPlayerTimeControlStatus.playing ? 1.0 : 0.0
    songInfo[MPMediaItemPropertyTitle] = trackName
    songInfo[MPMediaItemPropertyAlbumTitle] = albumName
    songInfo[MPMediaItemPropertyArtist] = artistName
    
    if duration != nil {
      songInfo[MPMediaItemPropertyPlaybackDuration] =  duration! / 1000
      songInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] =  (position * duration!) / 1000
    }
    if (image != nil) {
      songInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork.init(image: image!)
    }
    
    MPNowPlayingInfoCenter.default().nowPlayingInfo = songInfo
    MPNowPlayingInfoCenter.default().playbackState = player.rate == 0.0 ? .paused : .playing
  }
  
  func pause() {
    player.pause()
  }
  
  func resume() {
    player.play()
  }
  
  
  func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
    switch (status) {
    case AVPlayer.TimeControlStatus.playing:
      print("Playing.")
      channel.invokeMethod("onIsPlaying", arguments: nil)
      
    case AVPlayer.TimeControlStatus.paused:
      print("Paused.")
      channel.invokeMethod("onIsPaused", arguments: nil)
      
    case AVPlayer.TimeControlStatus.waitingToPlayAtSpecifiedRate:
      print("Waiting to play at specified rate.")
      channel.invokeMethod("onIsLoading", arguments: nil)
    }
    updateInfoCenter()
  }
  
  
  func durationChanged() {
    var newDuration: Double?
    
    if player.currentItem != nil && !CMTIME_IS_INDEFINITE(player.currentItem!.duration) {
      newDuration = player.currentItem!.duration.seconds * 1000
    }
    
    if newDuration != duration {
      duration = newDuration
      channel.invokeMethod("onDuration", arguments: duration == nil ? nil : lround(duration!))
    }
    updateInfoCenter()
  }
  
  func positionChanged(timer: Timer) {
    if duration == nil || player.currentItem == nil || CMTIME_IS_INDEFINITE(player.currentItem!.currentTime()) {
      // We don't want to do anything if we don't have a duration, currentItem or currentTime.
      return
    }
    
    let positionInMs = player.currentItem!.currentTime().seconds * 1000
    let positionPercent = positionInMs / duration!
    
    if positionPercent != position {
      position = positionPercent
      channel.invokeMethod("onPosition", arguments: position)
    }
  }
  
  func itemStatusChanged(_ status: AVPlayerItemStatus) {
    // Switch over status value
    switch status {
    case .readyToPlay:
      positionTimer = Timer.scheduledTimer(withTimeInterval: positionUpdateInterval, repeats: true, block:  self.positionChanged)
    case .failed:
      channel.invokeMethod("onError", arguments: ["code": 0, "message": "Playback failed"])
    case .unknown:
      channel.invokeMethod("onError", arguments: ["code": 0, "message": "Unknown error"])
    }
  }
}
