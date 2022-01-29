import 'dart:async';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import 'src/cover_image.dart' as cover_image;

abstract class ErrorCode {
  static const unkown = 0;
  static const unableToLoadFile = 1;
}

class PlaylistItem {
  /// Used to uniquely identify this track.
  final String id;
  final String url;
  final String artistName;
  final String albumName;
  final String trackName;
  final String coverUrl;

  /// In case the duration is known before hand, this can
  /// be provided so the native player can show the duration
  /// before the audio file is loaded.
  final Duration duration;

  /// If [id] is omitted, the [url] will be used as id.
  PlaylistItem({
    String id,
    @required String url,
    @required this.trackName,
    this.artistName,
    this.albumName,
    this.coverUrl,
    this.duration,
  })  : this.id = id ?? url,
        this.url = url;
}

class MusicPlayer {
  final _channel = MethodChannel('exit.live/music_player');

  // Outputs
  void Function(Duration duration) onDuration;
  void Function(double position) onPosition;

  // The different states
  void Function() onIsPlaying;
  void Function() onIsPaused;
  void Function() onIsLoading;
  void Function() onIsStopped;

  void Function() onCompleted;

  Function(int errorCode, [String errorMessage]) onError;

  MusicPlayer() {
    _setupOutputCallbacks();
  }

  List<PlaylistItem> _playlist;

  setPlaylist(List<PlaylistItem> playlist) async => _playlist = playlist;

  play(int playlistIndex) async {
    final playlistItem = _playlist[playlistIndex];

    await _channel.invokeMethod('play', {
      'url': playlistItem.url,
      'trackId': playlistItem.id,
      'trackName': playlistItem.trackName,
      'albumName': playlistItem.albumName,
      'artistName': playlistItem.artistName,
      'duration': playlistItem.duration?.inMilliseconds,
    });

    onDuration?.call(null);
    onPosition?.call(0.0);

    await _showCoverImage(playlistItem.coverUrl);
  }

  pause() => _channel.invokeMethod('pause');

  resume() => _channel.invokeMethod('resume');

  seek(double position) => _channel.invokeMethod('seek', position);

  /// Sets up the bridge to the native iOS and Android implementations.
  _setupOutputCallbacks() {
    Future<void> platformCallHandler(MethodCall call) async {
      // print('Output Callback: ${call.method}');
      switch (call.method) {
        case 'onDuration':
          final int durationInMilliseconds = call.arguments;
          onDuration?.call(Duration(milliseconds: durationInMilliseconds));
          break;
        case 'onPosition':
          final double position = call.arguments;
          onPosition?.call(position);
          break;
        case 'onIsLoading':
          onIsLoading?.call();
          break;
        case 'onIsPlaying':
          onIsPlaying?.call();
          break;
        case 'onIsPaused':
          onIsPaused?.call();
          break;
        case 'onIsStopped':
          onIsStopped?.call();
          break;
        case 'onCompleted':
          onCompleted?.call();
          break;
        case 'onError':
          final Map error = call.arguments;
          final int code = error['code'];
          final String message = error['message'];
          onError?.call(code, message);
          break;
        default:
          print('Unknowm method ${call.method}');
      }
    }

    _channel.setMethodCallHandler(platformCallHandler);
  }

  dispose() => _channel.setMethodCallHandler(null);

  Future<void> _showCoverImage(String coverUrl) async {
    try {
      final fileName = await cover_image.transferImage(coverUrl);
      if (fileName != null) {
        print('Saved cover $fileName, now telling the plugin.');
        await _channel.invokeMethod('showCover', fileName);
      }
    } catch (e) {
      print('Unable to load and show cover image: $e [ Ignoring ]');
    }
  }
}
