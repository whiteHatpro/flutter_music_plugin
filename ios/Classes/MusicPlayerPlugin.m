#import "MusicPlayerPlugin.h"
#import <music_player/music_player-Swift.h>

@implementation MusicPlayerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftMusicPlayerPlugin registerWithRegistrar:registrar];
}
@end
