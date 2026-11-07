// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.
//
// The command handling follows Chromium's BrowserNativeWidgetMac and
// ChromeCommandDispatcherDelegate (BSD-3-Clause), which reach the browser
// through Views' window bridge; a native window reaches it directly.

#import "chrome/browser/clair/window/clair_native_window.h"

#include "base/apple/foundation_util.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#import "chrome/browser/app_controller_mac.h"
#import "chrome/browser/clair/ClairHost.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/global_keyboard_shortcuts_mac.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_command_controller.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/grit/generated_resources.h"
#include "components/input/native_web_keyboard_event.h"
#import "ui/base/cocoa/cocoa_base_utils.h"
#import "ui/base/cocoa/user_interface_item_command_handler.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/window_open_disposition.h"

// Commands for D9's unavailable features, D10's removed bookmarks UI and
// D17's passwords and autofill. Their menu items stay hidden and disabled in a
// native window.
bool ClairIsRemovedCommand(int command) {
  switch (command) {
    case IDC_BOOKMARK_THIS_TAB:
    case IDC_BOOKMARK_ALL_TABS:
    case IDC_SHOW_BOOKMARK_BAR:
    case IDC_SHOW_BOOKMARK_SIDE_PANEL:
    case IDC_TOGGLE_FULLSCREEN_TOOLBAR:
    case IDC_SHOW_FULL_URLS:
    case IDC_SHOW_CUSTOMIZE_CHROME_SIDE_PANEL:
    case IDC_SHOW_CUSTOMIZE_CHROME_TOOLBAR:
    case IDC_TAB_SEARCH:
    case IDC_TAB_SEARCH_CLOSE:
    case IDC_CREATE_NEW_TAB_GROUP:
    case IDC_WINDOW_GROUP_TAB:
    case IDC_GROUP_TARGET_TAB:
    case IDC_SHOW_CHROME_LABS:
    case IDC_SHOW_READING_MODE_SIDE_PANEL:
    case IDC_READING_LIST_MENU_SHOW_UI:
    case IDC_TOGGLE_VERTICAL_TABS:
    case IDC_TOGGLE_VERTICAL_TABS_COLLAPSE:
    case IDC_SHOW_HISTORY_SIDE_PANEL:
    case IDC_NEW_SPLIT_TAB:
    // Omnibox settings, with no omnibox to apply to, and Cast.
    case IDC_SHOW_GOOGLE_LENS_SHORTCUT:
    case IDC_SHOW_AI_MODE_OMNIBOX_BUTTON:
    case IDC_SHOW_SEARCH_TOOLS:
    case IDC_ROUTE_MEDIA:
    // Passwords and autofill are off (D17).
    case IDC_SHOW_PASSWORD_MANAGER:
    case IDC_PASSWORDS_AND_AUTOFILL_MENU:
    case IDC_SHOW_PAYMENT_METHODS:
      return true;
    default:
      return false;
  }
}

namespace {

// Whether `event` fires `item`'s key equivalent.
bool FiresKeyEquivalent(NSMenuItem* item, NSEvent* event) {
  if (!item.keyEquivalent.length || item.hidden || !item.enabled) {
    return false;
  }
  const NSEventModifierFlags relevant =
      NSEventModifierFlagCommand | NSEventModifierFlagShift |
      NSEventModifierFlagOption | NSEventModifierFlagControl;
  NSEventModifierFlags wanted = item.keyEquivalentModifierMask & relevant;
  NSString* key = item.keyEquivalent;
  // An uppercase key equivalent implies Shift.
  if (![key.lowercaseString isEqualToString:key]) {
    wanted |= NSEventModifierFlagShift;
    key = key.lowercaseString;
  }
  return (event.modifierFlags & relevant) == wanted &&
         [event.charactersIgnoringModifiers.lowercaseString
             isEqualToString:key];
}

NSMenuItem* FindMenuItem(NSMenu* menu, NSInteger tag) {
  for (NSMenuItem* item in menu.itemArray) {
    if (item.tag == tag) {
      return item;
    }
    if (item.submenu) {
      if (NSMenuItem* found = FindMenuItem(item.submenu, tag)) {
        return found;
      }
    }
  }
  return nil;
}

// Runs `command` for the native window's browser, as BrowserNativeWidgetMac's
// ExecuteCommand does. In a native window, New Tab opens the command bar
// instead (D10). Returns whether the command ran.
bool ExecuteCommand(ClairBrowserWindow* window,
                    int command,
                    WindowOpenDisposition disposition,
                    bool is_before_first_responder) {
  if (!window) {
    return false;
  }
  Browser* browser = window->browser();
  if (is_before_first_responder) {
    // Only reserved commands bypass the page, as in Chromium.
    input::NativeWebKeyboardEvent dummy_event(
        blink::WebInputEvent::Type::kKeyDown, 0, base::TimeTicks());
    if (!chrome::BrowserCommandController::From(browser)
             ->IsReservedCommandOrKey(command, dummy_event)) {
      return false;
    }
  }
  if (command == IDC_NEW_TAB && window->clair_window()) {
    [window->clair_window() showCommandBarWithMode:ClairCommandBarModeNewTab];
    return true;
  }
  if (ClairIsRemovedCommand(command)) {
    return true;
  }
  chrome::ExecuteCommandWithDisposition(browser, command, disposition);
  return true;
}

}  // namespace

// Validates and runs Chromium's menu commands for a native window, as
// BrowserWindowCommandHandler does for Chromium's windows.
@interface ClairWindowCommandHandler : NSObject <UserInterfaceItemCommandHandler>
@end

@implementation ClairWindowCommandHandler

- (ClairBrowserWindow*)browserWindowFor:(NSWindow*)window {
  ClairNativeWindow* native = base::apple::ObjCCast<ClairNativeWindow>(window);
  return native ? native.browserWindow : nullptr;
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item
                           window:(NSWindow*)window {
  ClairBrowserWindow* browser_window = [self browserWindowFor:window];
  const int command = static_cast<int>(item.tag);
  NSMenuItem* menu_item = base::apple::ObjCCast<NSMenuItem>(item);
  if (!browser_window) {
    return NO;
  }
  Browser* browser = browser_window->browser();
  if (ClairIsRemovedCommand(command)) {
    menu_item.hidden = YES;
    return NO;
  }
  if (!chrome::SupportsCommand(browser, command)) {
    return NO;
  }
  BOOL enable = chrome::IsCommandEnabled(browser, command);
  switch (command) {
    case IDC_CLOSE_TAB:
      // app_controller_mac.mm decides whether the item has a shortcut.
      enable &= menu_item ? menu_item.keyEquivalent.length > 0 : YES;
      break;
    case IDC_FULLSCREEN:
      menu_item.title = l10n_util::GetNSString(
          browser_window->IsFullscreen() ? IDS_EXIT_FULLSCREEN_MAC
                                         : IDS_ENTER_FULLSCREEN_MAC);
      break;
    case IDC_SHOW_AS_TAB:
      menu_item.hidden = YES;
      break;
    case IDC_BACK:
    case IDC_DUPLICATE_TAB:
    case IDC_FOCUS_LOCATION:
    case IDC_FORWARD:
    case IDC_HOME:
    case IDC_MANAGE_EXTENSIONS:
    case IDC_MOVE_TAB_TO_NEW_WINDOW:
    case IDC_NEW_TAB:
    case IDC_OPEN_FILE:
    case IDC_PRINT:
    case IDC_RELOAD:
    case IDC_SAVE_PAGE:
    case IDC_SELECT_NEXT_TAB:
    case IDC_SELECT_PREVIOUS_TAB:
    case IDC_SHOW_DOWNLOADS:
    case IDC_STOP:
    case IDC_WINDOW_CLOSE_OTHER_TABS:
    case IDC_WINDOW_CLOSE_TABS_TO_RIGHT:
      // Commands that would put up their own dialog are off while a modal
      // dialog is up.
      enable &= ![AppController.sharedController keyWindowIsModal];
      break;
    default:
      break;
  }
  return enable;
}

- (void)commandDispatch:(id)sender window:(NSWindow*)window {
  ExecuteCommand([self browserWindowFor:window], static_cast<int>([sender tag]),
                 WindowOpenDisposition::CURRENT_TAB,
                 /*is_before_first_responder=*/false);
}

- (void)commandDispatchUsingKeyModifiers:(id)sender window:(NSWindow*)window {
  if ([sender respondsToSelector:@selector(isEnabled)] && ![sender isEnabled]) {
    return;
  }
  ExecuteCommand([self browserWindowFor:window], static_cast<int>([sender tag]),
                 ui::WindowOpenDispositionFromNSEvent(NSApp.currentEvent),
                 /*is_before_first_responder=*/false);
}

@end

// Chromium's key-equivalent order for a native window, as
// ChromeCommandDispatcherDelegate has it: reserved commands before the page,
// the rest after the page declined them. View > Hide Sidebar counts as
// reserved, so a page can't keep Cmd+S from it.
@interface ClairCommandDispatcherDelegate : NSObject <CommandDispatcherDelegate>
@end

@implementation ClairCommandDispatcherDelegate

- (ClairBrowserWindow*)browserWindowFor:(NSWindow*)window {
  ClairNativeWindow* native = base::apple::ObjCCast<ClairNativeWindow>(window);
  return native ? native.browserWindow : nullptr;
}

- (ui::PerformKeyEquivalentResult)prePerformKeyEquivalent:(NSEvent*)event
                                                   window:(NSWindow*)window {
  NSResponder* responder = window.firstResponder;
  if ([responder respondsToSelector:@selector(isKeyLocked:)] &&
      [(id)responder isKeyLocked:event]) {
    return ui::PerformKeyEquivalentResult::kUnhandled;
  }

  NSMenuItem* hide_sidebar = FindMenuItem(NSApp.mainMenu, kClairHideSidebarTag);
  if (hide_sidebar && FiresKeyEquivalent(hide_sidebar, event)) {
    [NSApp sendAction:hide_sidebar.action to:hide_sidebar.target from:hide_sidebar];
    return ui::PerformKeyEquivalentResult::kHandled;
  }

  CommandForKeyEventResult result = CommandForKeyEvent(event);
  if (event.isARepeat && (result.chrome_command == IDC_NEW_TAB ||
                          result.chrome_command == IDC_NEW_WINDOW ||
                          result.chrome_command == IDC_NEW_INCOGNITO_WINDOW)) {
    return ui::PerformKeyEquivalentResult::kDrop;
  }
  if (!result.found()) {
    return ui::PerformKeyEquivalentResult::kUnhandled;
  }
  const bool executed =
      ExecuteCommand([self browserWindowFor:window], result.chrome_command,
                     WindowOpenDisposition::CURRENT_TAB,
                     /*is_before_first_responder=*/true);
  return executed ? ui::PerformKeyEquivalentResult::kHandled
                  : ui::PerformKeyEquivalentResult::kUnhandled;
}

- (ui::PerformKeyEquivalentResult)postPerformKeyEquivalent:(NSEvent*)event
                                                    window:(NSWindow*)window
                                              isRedispatch:(BOOL)isRedispatch {
  CommandForKeyEventResult result = CommandForKeyEvent(event);
  if (!result.found() && isRedispatch) {
    result.chrome_command = DelayedWebContentsCommandForKeyEvent(event);
    result.from_main_menu = false;
  }
  if (!result.found()) {
    return ui::PerformKeyEquivalentResult::kUnhandled;
  }
  if (result.from_main_menu) {
    return ui::PerformKeyEquivalentResult::kPassToMainMenu;
  }
  ExecuteCommand([self browserWindowFor:window], result.chrome_command,
                 WindowOpenDisposition::CURRENT_TAB,
                 /*is_before_first_responder=*/false);
  return ui::PerformKeyEquivalentResult::kHandled;
}

@end

// Tells the browser window about the NSWindow's activation, geometry, full
// screen and close button.
@interface ClairNativeWindowDelegate : NSObject <NSWindowDelegate>
@property(nonatomic, weak) ClairNativeWindow* window;
@end

@implementation ClairNativeWindowDelegate

- (ClairBrowserWindow*)browserWindow {
  return self.window.browserWindow;
}

- (BOOL)windowShouldClose:(NSWindow*)sender {
  if (ClairBrowserWindow* browser_window = self.browserWindow) {
    browser_window->WindowCloseRequested();
  }
  // Chromium closes the window itself once its tabs have closed.
  return NO;
}

- (void)windowDidBecomeKey:(NSNotification*)notification {
  if (ClairBrowserWindow* browser_window = self.browserWindow) {
    browser_window->WindowDidBecomeKey();
  }
}

- (void)windowDidResignKey:(NSNotification*)notification {
  if (ClairBrowserWindow* browser_window = self.browserWindow) {
    browser_window->WindowDidResignKey();
  }
}

- (void)windowDidMove:(NSNotification*)notification {
  if (ClairBrowserWindow* browser_window = self.browserWindow) {
    browser_window->WindowGeometryChanged();
  }
}

- (void)windowDidResize:(NSNotification*)notification {
  if (ClairBrowserWindow* browser_window = self.browserWindow) {
    browser_window->WindowGeometryChanged();
  }
}

- (void)windowDidMiniaturize:(NSNotification*)notification {
  if (ClairBrowserWindow* browser_window = self.browserWindow) {
    browser_window->WindowGeometryChanged();
  }
}

- (void)windowDidDeminiaturize:(NSNotification*)notification {
  if (ClairBrowserWindow* browser_window = self.browserWindow) {
    browser_window->WindowGeometryChanged();
  }
}

- (void)windowDidEnterFullScreen:(NSNotification*)notification {
  if (ClairBrowserWindow* browser_window = self.browserWindow) {
    browser_window->WindowFullscreenChanged(true);
  }
}

- (void)windowDidExitFullScreen:(NSNotification*)notification {
  if (ClairBrowserWindow* browser_window = self.browserWindow) {
    browser_window->WindowFullscreenChanged(false);
  }
}

@end

@implementation ClairNativeWindow {
  ClairBrowserWindow* _browserWindow;  // Weak; owns this window.
  CommandDispatcher* __strong _commandDispatcher;
  ClairCommandDispatcherDelegate* __strong _commandDispatcherDelegate;
  id<UserInterfaceItemCommandHandler> __strong _commandHandler;
  ClairNativeWindowDelegate* __strong _windowDelegate;
}

- (instancetype)initWithBrowserWindow:(ClairBrowserWindow*)browserWindow
                          contentRect:(NSRect)contentRect {
  const NSWindowStyleMask style =
      NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
      NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
      NSWindowStyleMaskFullSizeContentView;
  if ((self = [super initWithContentRect:contentRect
                               styleMask:style
                                 backing:NSBackingStoreBuffered
                                   defer:YES])) {
    _browserWindow = browserWindow;
    self.releasedWhenClosed = NO;
    self.collectionBehavior = NSWindowCollectionBehaviorFullScreenPrimary;
    _commandDispatcher = [[CommandDispatcher alloc] initWithOwner:self];
    _commandDispatcherDelegate = [[ClairCommandDispatcherDelegate alloc] init];
    _commandDispatcher.delegate = _commandDispatcherDelegate;
    _commandHandler = [[ClairWindowCommandHandler alloc] init];
    _windowDelegate = [[ClairNativeWindowDelegate alloc] init];
    _windowDelegate.window = self;
    self.delegate = _windowDelegate;
  }
  return self;
}

- (ClairBrowserWindow*)browserWindow {
  return _browserWindow;
}

- (void)detachBrowserWindow {
  _browserWindow = nullptr;
}

// Let CommandDispatcher recognize events it is redispatching.
- (void)sendEvent:(NSEvent*)event {
  if ([_commandDispatcher preSendEvent:event]) {
    return;
  }
  if (_browserWindow && _browserWindow->HandleExclusiveAccessKey(event)) {
    return;
  }
  [super sendEvent:event];
}

- (BOOL)performKeyEquivalent:(NSEvent*)event {
  return [_commandDispatcher performKeyEquivalent:event];
}

- (BOOL)respondsToSelector:(SEL)selector {
  // Without a browser there are no commands to dispatch.
  if ((selector == @selector(commandDispatch:) ||
       selector == @selector(commandDispatchUsingKeyModifiers:)) &&
      !_browserWindow) {
    return NO;
  }
  return [super respondsToSelector:selector];
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  return [_commandDispatcher validateUserInterfaceItem:item
                                            forHandler:_commandHandler];
}

// CommandDispatchingWindow:

- (NSWindow<CommandDispatchingWindow>*)commandDispatchParent {
  return nil;
}

- (void)setCommandHandler:(id<UserInterfaceItemCommandHandler>)commandHandler {
  _commandHandler = commandHandler;
}

- (CommandDispatcher*)commandDispatcher {
  return _commandDispatcher;
}

- (BOOL)defaultPerformKeyEquivalent:(NSEvent*)event {
  return [super performKeyEquivalent:event];
}

- (BOOL)defaultValidateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)item {
  return [super validateUserInterfaceItem:item];
}

- (void)commandDispatch:(id)sender {
  [_commandDispatcher dispatch:sender forHandler:_commandHandler];
}

- (void)commandDispatchUsingKeyModifiers:(id)sender {
  [_commandDispatcher dispatchUsingKeyModifiers:sender
                                     forHandler:_commandHandler];
}

@end
