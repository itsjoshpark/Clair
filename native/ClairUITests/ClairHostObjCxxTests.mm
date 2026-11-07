// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// Compiles ClairHost.h in an Objective-C++ unit, as Chromium does, and checks
// ClairUI.framework the way Chromium's loader will: by its principal class.

#import <XCTest/XCTest.h>

#include <string>

#import <objc/runtime.h>

#import "ClairHost.h"

@interface ObjCxxHost : NSObject <ClairHost>
@end

@implementation ObjCxxHost
- (NSString*)chromiumVersion {
  return @(std::string("156.0.8078.73").c_str());
}
- (NSString*)ungoogledChromiumVersion {
  return @"156.0.8078.73-1";
}
- (ClairRelaunchBlockers)silentRelaunchBlockers {
  return ClairRelaunchBlockersIncognitoWindow | ClairRelaunchBlockersCapturingTab;
}
- (void)relaunch {
}
- (void)updateWillInstallOnQuit {
}
- (void)openURL:(NSURL*)url {
}
@end

@interface ClairHostObjCxxTests : XCTestCase
@end

@implementation ClairHostObjCxxTests

- (void)testHostCompilesInObjectiveCxx {
  id<ClairHost> host = [[ObjCxxHost alloc] init];
  XCTAssertTrue([host conformsToProtocol:@protocol(ClairHost)]);
  XCTAssertEqualObjects(host.chromiumVersion, @"156.0.8078.73");
  XCTAssertEqual(host.silentRelaunchBlockers & ClairRelaunchBlockersIncognitoWindow,
                 ClairRelaunchBlockersIncognitoWindow);
}

// The window contract's value types and protocols, used from C++ as the
// overlay uses them.
- (void)testWindowContractCompilesInObjectiveCxx {
  ClairDevToolsLayout layout = {ClairDevToolsDockSideRight, NSMakeRect(0, 0, 640, 480), false};
  XCTAssertEqual(layout.dockSide, ClairDevToolsDockSideRight);
  ClairAnchor anchor = {NSMakeRect(12, 700, 24, 24), ClairAnchorEdgeTrailing};
  XCTAssertEqual(anchor.edge, ClairAnchorEdgeTrailing);
  ClairFindResult find = {1, 3, true};
  XCTAssertEqual(find.matchCount, 3);
  ClairTabIndicators indicators = ClairTabIndicatorsCamera | ClairTabIndicatorsBlockedPermission;
  XCTAssertTrue(indicators & ClairTabIndicatorsCamera);
  ClairTabID none = ClairTabIDNone;
  XCTAssertEqual(none, -1);
  std::string kinds[] = {"regular", "incognito", "guest"};
  XCTAssertEqual(kinds[ClairProfileKindGuest], "guest");
  for (Protocol* protocol in @[
         @protocol(ClairBrowser), @protocol(ClairWindow), @protocol(ClairTab),
         @protocol(ClairAutocomplete), @protocol(ClairAutocompleteDelegate),
         @protocol(ClairSuggestion), @protocol(ClairDownload),
         @protocol(ClairExtensionAction), @protocol(ClairInfobar)
       ]) {
    XCTAssertTrue(protocol_conformsToProtocol(protocol, @protocol(NSObject)));
  }
}

- (void)testFrameworkPrincipalClassConformsToEntryPoint {
  NSBundle* bundle = [NSBundle bundleWithIdentifier:@"dev.joshuapark.Clair.ClairUI"];
  XCTAssertNotNil(bundle);
  XCTAssertTrue([bundle load]);
  Class principal = bundle.principalClass;
  XCTAssertNotNil(principal);
  XCTAssertTrue([principal conformsToProtocol:@protocol(ClairUIEntryPoint)]);
  XCTAssertTrue([principal respondsToSelector:@selector(startWithHost:)]);
  XCTAssertTrue([principal respondsToSelector:@selector(windowForBrowser:)]);
}

@end
