// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_BROWSER_BRIDGE_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_BROWSER_BRIDGE_H_

#import <AppKit/AppKit.h>

#include <string>

#import "chrome/browser/clair/ClairHost.h"

class ClairBrowserWindow;

namespace content {
class WebContents;
}  // namespace content

// Chromium's side of one native window's contract (design D3): ClairUI's
// commands come in here, and Chromium's changes go out to the ClairWindow,
// coalesced to once per run-loop turn. The window's tabs reach ClairUI
// through the host's Spaces observer (add-spaces D9). ClairUI gets value
// snapshots and IDs, never anything wrapping a C++ object.
@interface ClairChromiumBrowser : NSObject <ClairBrowser>

- (instancetype)initWithBrowserWindow:(ClairBrowserWindow*)browserWindow;

// Starts telling `window` what changes. Before this, nothing is posted.
- (void)attachWindow:(id<ClairWindow>)window;

// The browser window is closing: every later call does nothing, and nothing
// more is posted.
- (void)detach;

// What changed, to post at the end of this run-loop turn. Tab lists and tab
// changes go through the profile's ClairSpaceTabs (add-spaces D9).
- (void)tabListChanged;
- (void)tabChanged:(content::WebContents*)contents;
// The window shows another Space; `previousSpace` is the one it showed.
- (void)shownSpaceChangedFrom:(const std::string&)previousSpace;
// add-profiles D3: the window's group swaps it in from a member showing
// `previousSpace`, which ClairUI hears as the Space shown before, whatever
// this window showed.
- (void)swappedInFrom:(const std::string&)previousSpace;
- (void)activeTabChanged;
// The window's still started, ended or got its image
// (share-tabs-across-windows D2).
- (void)stillChanged;
// Tells ClairUI now, without waiting for the end of the turn.
- (void)flush;

// A snapshot of `contents`, which must be in this browser's tab strip.
- (id<ClairTab>)snapshotOf:(content::WebContents*)contents;

@end

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_BROWSER_BRIDGE_H_
