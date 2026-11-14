// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_NATIVE_WINDOW_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_NATIVE_WINDOW_H_

#import <AppKit/AppKit.h>

#import "chrome/browser/clair/ClairHost.h"
#import "ui/base/cocoa/command_dispatcher.h"

class ClairBrowserWindow;

// Whether `command` belongs to a feature the native window doesn't host (D9,
// D10, D17). Its menu item is hidden, and running it does nothing.
bool ClairIsRemovedCommand(int command);

// The tag of View > Hide Sidebar, which the overlay adds to the main menu
// (D10). Chromium's command IDs stay below 0xFFFF.
inline constexpr NSInteger kClairHideSidebarTag = 0x436C6169;  // 'Clai'

// The NSWindow of a native browser window (design D4). Chromium creates it and
// hands it to ClairUI, which styles and fills it. It dispatches Chromium's
// commands and key equivalents through CommandDispatcher, as Chromium's own
// windows do, so the menus, reserved shortcuts and keys a page didn't handle
// work as in Chromium, and chrome::FindBrowserWithWindow() finds its browser.
//
// It places its close, minimize and zoom buttons through AppKit's own title bar
// layout (ClairWindowControls; place-traffic-lights-with-appkit design D1), as
// Chromium's BrowserNativeWidgetWindow does, so no title bar layout moves them.
@interface ClairNativeWindow
    : NSWindow <CommandDispatchingWindow, ClairWindowControls>

- (instancetype)initWithBrowserWindow:(ClairBrowserWindow*)browserWindow
                          contentRect:(NSRect)contentRect;

// The browser window, until it is destroyed.
@property(nonatomic, readonly) ClairBrowserWindow* browserWindow;

// add-profiles D4: the window covers its group's full-screen window: its
// window controls hide, and it may lie over the menu bar's place.
@property(nonatomic) BOOL covering;

// Called when the browser window is destroyed; the window then forwards
// nothing.
- (void)detachBrowserWindow;

@end

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_NATIVE_WINDOW_H_
