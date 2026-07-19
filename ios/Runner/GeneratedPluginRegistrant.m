//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<ffmpeg_kit_flutter_new/FFmpegKitFlutterPlugin.h>)
#import <ffmpeg_kit_flutter_new/FFmpegKitFlutterPlugin.h>
#else
@import ffmpeg_kit_flutter_new;
#endif

#if __has_include(<flutter_inappwebview_ios/InAppWebViewFlutterPlugin.h>)
#import <flutter_inappwebview_ios/InAppWebViewFlutterPlugin.h>
#else
@import flutter_inappwebview_ios;
#endif

#if __has_include(<share_plus/FPPSharePlusPlugin.h>)
#import <share_plus/FPPSharePlusPlugin.h>
#else
@import share_plus;
#endif

#if __has_include(<video_player_avfoundation/VideoPlayerPlugin.h>)
#import <video_player_avfoundation/VideoPlayerPlugin.h>
#else
@import video_player_avfoundation;
#endif

#if __has_include(<video_thumbnail/VideoThumbnailPlugin.h>)
#import <video_thumbnail/VideoThumbnailPlugin.h>
#else
@import video_thumbnail;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [FFmpegKitFlutterPlugin registerWithRegistrar:[registry registrarForPlugin:@"FFmpegKitFlutterPlugin"]];
  [InAppWebViewFlutterPlugin registerWithRegistrar:[registry registrarForPlugin:@"InAppWebViewFlutterPlugin"]];
  [FPPSharePlusPlugin registerWithRegistrar:[registry registrarForPlugin:@"FPPSharePlusPlugin"]];
  [VideoPlayerPlugin registerWithRegistrar:[registry registrarForPlugin:@"VideoPlayerPlugin"]];
  [VideoThumbnailPlugin registerWithRegistrar:[registry registrarForPlugin:@"VideoThumbnailPlugin"]];
}

@end
