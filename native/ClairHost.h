// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.
//
// ClairHost.h: the one contract between Chromium and Clair's native layer,
// ClairUI.framework (change 1, native-layer spec and design D4).
//
// Chromium loads ClairUI.framework from Clair.app/Contents/Frameworks once it
// has built the main menu, takes the bundle's principal class, checks that it
// conforms to ClairUIEntryPoint, and calls +startWithHost: with its
// implementation of ClairHost. ClairUI reaches Chromium only through that host,
// and Chromium reaches ClairUI only through that entry point.
//
// The header is plain Objective-C, so Chromium includes it from Objective-C++
// and Swift imports it as the ClairHost module (native/module.modulemap).
// Every call happens on the main thread.
//
// It is an engine input (scripts/engine-key.sh): a change here needs a new
// engine, so keep it small and add to it only what ClairUI needs.

#ifndef CLAIR_NATIVE_CLAIR_HOST_H_
#define CLAIR_NATIVE_CLAIR_HOST_H_

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Why relaunching Clair now, without asking, would interrupt the user. Each
// set bit is one reason; none set means a silent relaunch is safe.
typedef NS_OPTIONS(NSUInteger, ClairRelaunchBlockers) {
  ClairRelaunchBlockersNone = 0,
  // A download is in progress; quitting would cancel it.
  ClairRelaunchBlockersDownloadInProgress = 1 << 0,
  // An incognito window is open; it doesn't come back after a relaunch.
  ClairRelaunchBlockersIncognitoWindow = 1 << 1,
  // A tab is playing sound.
  ClairRelaunchBlockersAudibleTab = 1 << 2,
  // A tab is capturing the camera, microphone or screen.
  ClairRelaunchBlockersCapturingTab = 1 << 3,
} NS_SWIFT_NAME(RelaunchBlockers);

// What Chromium does for ClairUI. Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairHost)
@protocol ClairHost <NSObject>

// The Chromium version compiled into the engine, such as "156.0.8078.73".
// It is also what websites and extensions see.
@property(nonatomic, readonly, copy) NSString *chromiumVersion;

// The ungoogled-chromium release the engine was built from, such as
// "156.0.8078.73-1".
@property(nonatomic, readonly, copy) NSString *ungoogledChromiumVersion;

// What would make a relaunch without asking interrupt the user right now.
- (ClairRelaunchBlockers)silentRelaunchBlockers;

// Quits and reopens Clair through Chromium's own graceful relaunch, which
// restores the open windows and tabs. Chromium's quit confirmations still
// apply, so the user can cancel, for example while a download is running.
- (void)relaunch;

@end

// What ClairUI.framework's principal class (NSPrincipalClass) implements.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairUIEntryPoint)
@protocol ClairUIEntryPoint <NSObject>

// Called once, after Chromium has built the main menu. ClairUI keeps `host`
// for as long as the app runs.
+ (void)startWithHost:(id<ClairHost>)host NS_SWIFT_NAME(start(host:));

@end

NS_ASSUME_NONNULL_END

#endif  // CLAIR_NATIVE_CLAIR_HOST_H_

// engine-check test: throwaway, never merged
