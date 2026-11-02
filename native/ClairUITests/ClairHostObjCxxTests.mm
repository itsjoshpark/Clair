// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.

// Compiles ClairHost.h in an Objective-C++ unit, as Chromium does, and checks
// ClairUI.framework the way Chromium's loader will: by its principal class.

#import <XCTest/XCTest.h>

#include <string>

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

- (void)testFrameworkPrincipalClassConformsToEntryPoint {
  NSBundle* bundle = [NSBundle bundleWithIdentifier:@"dev.joshuapark.Clair.ClairUI"];
  XCTAssertNotNil(bundle);
  XCTAssertTrue([bundle load]);
  Class principal = bundle.principalClass;
  XCTAssertNotNil(principal);
  XCTAssertTrue([principal conformsToProtocol:@protocol(ClairUIEntryPoint)]);
  XCTAssertTrue([principal respondsToSelector:@selector(startWithHost:)]);
}

@end
