//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<integration_test/IntegrationTestPlugin.h>)
#import <integration_test/IntegrationTestPlugin.h>
#else
@import integration_test;
#endif

#if __has_include(<op_wifi_utils/SwiftOpWifiUtilsPlugin.h>)
#import <op_wifi_utils/SwiftOpWifiUtilsPlugin.h>
#else
@import op_wifi_utils;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [IntegrationTestPlugin registerWithRegistrar:[registry registrarForPlugin:@"IntegrationTestPlugin"]];
  [SwiftOpWifiUtilsPlugin registerWithRegistrar:[registry registrarForPlugin:@"SwiftOpWifiUtilsPlugin"]];
}

@end
