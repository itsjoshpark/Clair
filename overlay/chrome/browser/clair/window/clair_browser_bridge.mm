// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#import "chrome/browser/clair/window/clair_browser_bridge.h"

#include <algorithm>
#include <climits>
#include <memory>
#include <optional>
#include <set>
#include <vector>

#include "base/check.h"
#include "base/functional/callback_helpers.h"
#include "base/logging.h"
#include "base/memory/raw_ptr.h"
#include "base/scoped_multi_source_observation.h"
#include "base/strings/escape.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/app/chrome_command_ids.h"
#import "chrome/browser/clair/window/clair_autocomplete.h"
#import "chrome/browser/clair/window/clair_native_window.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/clair/window/clair_downloads.h"
#include "chrome/browser/clair/window/clair_extensions.h"
#include "chrome/browser/clair/window/clair_peeks.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#include "chrome/browser/devtools/devtools_contents_resizing_strategy.h"
#include "chrome/browser/devtools/devtools_window.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ssl/chrome_security_state_util.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/bubble_anchor_util.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/page_info/page_info_dialog.h"
#include "chrome/browser/ui/recently_audible_helper.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_muted_utils.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model_observer.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "chrome/browser/ui/toolbar/back_forward_menu_model.h"
#include "chrome/common/webui_url_constants.h"
#include "components/content_settings/browser/page_specific_content_settings.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/confirm_infobar_delegate.h"
#include "components/infobars/core/infobar.h"
#include "components/infobars/core/infobar_manager.h"
#include "components/security_state/core/security_state.h"
#include "components/tabs/public/tab_context_menu_command.h"
#include "components/tabs/public/tab_interface.h"
#include "components/url_formatter/url_formatter.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_entry.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/common/url_constants.h"
#include "net/base/apple/url_conversions.h"
#include "ui/base/models/image_model.h"
#include "ui/base/models/menu_model_delegate.h"
#include "ui/base/window_open_disposition.h"
#include "ui/events/event_constants.h"
#include "ui/gfx/image/image.h"
#include "url/gurl.h"
#include "url/url_constants.h"

namespace {

ClairTabID TabIDOf(content::WebContents* contents) {
  tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  return tab ? tab->GetHandle().raw_value() : ClairTabIDNone;
}

WindowOpenDisposition DispositionFor(ClairOpenDisposition disposition) {
  switch (disposition) {
    case ClairOpenDispositionCurrentTab:
      return WindowOpenDisposition::CURRENT_TAB;
    case ClairOpenDispositionNewForegroundTab:
      return WindowOpenDisposition::NEW_FOREGROUND_TAB;
    case ClairOpenDispositionNewBackgroundTab:
      return WindowOpenDisposition::NEW_BACKGROUND_TAB;
    case ClairOpenDispositionNewWindow:
      return WindowOpenDisposition::NEW_WINDOW;
  }
  return WindowOpenDisposition::CURRENT_TAB;
}

NSInteger InfobarIDOf(const infobars::InfoBar* infobar) {
  return reinterpret_cast<NSInteger>(infobar);
}

}  // namespace

// --- History menu (design D3) -----------------------------------------------

@interface ClairChromiumHistoryItem : NSObject <ClairHistoryItem>
- (instancetype)initWithID:(NSInteger)itemID
                      kind:(ClairHistoryItemKind)kind
                     title:(NSString*)title
                       url:(NSURL*)url
                      icon:(NSImage*)icon;
@end

@implementation ClairChromiumHistoryItem
@synthesize itemID = _itemID;
@synthesize kind = _kind;
@synthesize title = _title;
@synthesize url = _url;
@synthesize icon = _icon;

- (instancetype)initWithID:(NSInteger)itemID
                      kind:(ClairHistoryItemKind)kind
                     title:(NSString*)title
                       url:(NSURL*)url
                      icon:(NSImage*)icon {
  if ((self = [super init])) {
    _itemID = itemID;
    _kind = kind;
    _title = [title copy];
    _url = [url copy];
    _icon = icon;
  }
  return self;
}
@end

@interface ClairChromiumHistoryMenu : NSObject <ClairHistoryMenu>
- (instancetype)initWithBrowser:(Browser*)browser
                      direction:(ClairHistoryDirection)direction
                       delegate:(id<ClairHistoryMenuDelegate>)delegate;
// Whether the menu lists any page; a session without one isn't handed out.
@property(nonatomic, readonly) BOOL hasPages;
// Chromium's model changed: a favicon arrived or the tab navigated.
- (void)modelChanged;
// Another tab became active: the session ends with an empty list.
- (void)activeTabChanged;
@end

namespace {

// Forwards BackForwardMenuModel's changes to its session.
class HistoryMenuModelDelegate : public ui::MenuModelDelegate {
 public:
  explicit HistoryMenuModelDelegate(ClairChromiumHistoryMenu* session)
      : session_(session) {}

  // ui::MenuModelDelegate:
  void OnIconChanged(int command_id) override { [session_ modelChanged]; }
  void OnMenuStructureChanged() override { [session_ modelChanged]; }

 private:
  ClairChromiumHistoryMenu* __weak session_;
};

int EventFlagsFor(ClairOpenDisposition disposition) {
  // What ui::DispositionFromEventFlags() turns back into `disposition` on
  // macOS, where Cmd is the new-tab modifier.
  switch (disposition) {
    case ClairOpenDispositionCurrentTab:
      return ui::EF_NONE;
    case ClairOpenDispositionNewForegroundTab:
      return ui::EF_COMMAND_DOWN | ui::EF_SHIFT_DOWN;
    case ClairOpenDispositionNewBackgroundTab:
      return ui::EF_COMMAND_DOWN;
    case ClairOpenDispositionNewWindow:
      return ui::EF_SHIFT_DOWN;
  }
  return ui::EF_NONE;
}

}  // namespace

@implementation ClairChromiumHistoryMenu {
  raw_ptr<Browser> _browser;
  ClairHistoryDirection _direction;
  base::WeakPtr<content::WebContents> _contents;
  std::unique_ptr<HistoryMenuModelDelegate> _modelDelegate;
  std::unique_ptr<BackForwardMenuModel> _model;
  id<ClairHistoryMenuDelegate> __weak _delegate;
  BOOL _changePosted;
}

- (instancetype)initWithBrowser:(Browser*)browser
                      direction:(ClairHistoryDirection)direction
                       delegate:(id<ClairHistoryMenuDelegate>)delegate {
  if ((self = [super init])) {
    _browser = browser;
    _direction = direction;
    _delegate = delegate;
    content::WebContents* active =
        browser->tab_strip_model()->GetActiveWebContents();
    if (active) {
      _contents = active->GetWeakPtr();
      _modelDelegate = std::make_unique<HistoryMenuModelDelegate>(self);
      _model = std::make_unique<BackForwardMenuModel>(
          browser, direction == ClairHistoryDirectionForward
                       ? BackForwardMenuModel::ModelType::kForward
                       : BackForwardMenuModel::ModelType::kBackward);
      // The model fetches missing favicons only while it has a delegate, and
      // ActivatedAt() expects MenuWillShow() first, as a shown menu calls it.
      _model->SetMenuModelDelegate(_modelDelegate.get());
      _model->MenuWillShow();
    }
  }
  return self;
}

- (void)dealloc {
  [self close];
}

// The tab the menu was opened for, while it's still the active tab.
- (content::WebContents*)liveContents {
  if (!_model || !_browser || !_contents) {
    return nullptr;
  }
  content::WebContents* active =
      _browser->tab_strip_model()->GetActiveWebContents();
  return active == _contents.get() ? active : nullptr;
}

- (BOOL)hasPages {
  return [self liveContents] &&
         _model->GetSectionItemCount(
             BackForwardMenuModel::MenuSection::kHistory) > 0;
}

- (NSArray<id<ClairHistoryItem>>*)items {
  content::WebContents* contents = [self liveContents];
  if (!contents) {
    return @[];
  }
  using Section = BackForwardMenuModel::MenuSection;
  NSMutableArray<id<ClairHistoryItem>>* items = [NSMutableArray array];
  content::NavigationController& controller = contents->GetController();
  const int current = controller.GetCurrentEntryIndex();
  const bool forward = _direction == ClairHistoryDirectionForward;
  if (std::optional<size_t> start =
          _model->GetStartingIndexOfSection(Section::kHistory)) {
    const size_t count = _model->GetSectionItemCount(Section::kHistory);
    for (size_t i = 0; i < count; ++i) {
      // The model's history section lists the entries next to the current
      // one, nearest first (BackForwardMenuModel::MenuIndexToNavEntryIndex).
      const int offset = static_cast<int>(i) + 1;
      content::NavigationEntry* entry = controller.GetEntryAtIndex(
          forward ? current + offset : current - offset);
      if (!entry) {
        continue;
      }
      const size_t index = *start + i;
      // Asking for the icon starts a favicon fetch for an entry without one;
      // it arrives through OnIconChanged().
      ui::ImageModel icon = _model->GetIconAt(index);
      NSImage* image = icon.IsImage() && !icon.GetImage().IsEmpty()
                           ? icon.GetImage().ToNSImage()
                           : nil;
      const GURL& url = entry->GetVirtualURL();
      [items addObject:[[ClairChromiumHistoryItem alloc]
                           initWithID:static_cast<NSInteger>(index)
                                 kind:ClairHistoryItemKindPage
                                title:base::SysUTF16ToNSString(
                                          entry->GetTitleForDisplay())
                                  url:url.is_valid() ? net::NSURLWithGURL(url)
                                                     : nil
                                 icon:image]];
    }
  }
  // Chapter stops and the back-to-opener entry are left out (design D3).
  if (std::optional<size_t> index =
          _model->GetStartingIndexOfSection(Section::kShowFullHistory)) {
    [items addObject:[[ClairChromiumHistoryItem alloc]
                         initWithID:static_cast<NSInteger>(*index)
                               kind:ClairHistoryItemKindShowFullHistory
                              title:base::SysUTF16ToNSString(
                                        _model->GetLabelAt(*index))
                                url:nil
                               icon:nil]];
  }
  return items;
}

- (void)modelChanged {
  if (_changePosted || !_model) {
    return;
  }
  _changePosted = YES;
  ClairChromiumHistoryMenu* __weak weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    ClairChromiumHistoryMenu* strongSelf = weakSelf;
    if (!strongSelf) {
      return;
    }
    strongSelf->_changePosted = NO;
    if (strongSelf->_model) {
      [strongSelf->_delegate historyMenu:strongSelf
                          itemsDidChange:strongSelf.items];
    }
  });
}

- (void)activeTabChanged {
  if (!_model) {
    return;
  }
  id<ClairHistoryMenuDelegate> delegate = _delegate;
  [self close];
  [delegate historyMenu:self itemsDidChange:@[]];
}

- (void)openItem:(NSInteger)itemID disposition:(ClairOpenDisposition)disposition {
  if (![self liveContents] || itemID < 0 ||
      static_cast<size_t>(itemID) >= _model->GetItemCount()) {
    return;
  }
  using Section = BackForwardMenuModel::MenuSection;
  const size_t index = static_cast<size_t>(itemID);
  const std::optional<Section> section = _model->GetSectionForIndex(index);
  if (section == Section::kHistory || section == Section::kShowFullHistory) {
    // Chromium's own navigation and new-tab code (design D3).
    _model->ActivatedAt(index, EventFlagsFor(disposition));
  }
  [self close];
}

- (void)close {
  if (!_model) {
    return;
  }
  _model->MenuWillClose();
  _model->SetMenuModelDelegate(nullptr);
  _model.reset();
  _modelDelegate.reset();
  _browser = nullptr;
}

@end

// --- The bridge --------------------------------------------------------------

@implementation ClairChromiumBrowser {
  ClairBrowserWindow* _browserWindow;  // Weak; owns this bridge.
  id<ClairWindow> __weak _window;
  BOOL _flushPosted;
  BOOL _activeTabChanged;
  // add-spaces D3: the Space the window showed before the change ClairUI
  // hasn't heard of yet.
  std::optional<std::string> _previousSpace;
  ClairChromiumHistoryMenu* __weak _historyMenu;
}

- (instancetype)initWithBrowserWindow:(ClairBrowserWindow*)browserWindow {
  if ((self = [super init])) {
    _browserWindow = browserWindow;
  }
  return self;
}

- (void)attachWindow:(id<ClairWindow>)window {
  _window = window;
}

- (void)detach {
  [_historyMenu close];
  _browserWindow = nullptr;
  _window = nil;
}

- (Browser*)browser {
  return _browserWindow ? _browserWindow->browser() : nullptr;
}

- (TabStripModel*)tabStrip {
  Browser* browser = self.browser;
  return browser ? browser->tab_strip_model() : nullptr;
}

// The tab strip index of `tabID`, or kNoTab.
- (int)indexOfTab:(ClairTabID)tabID {
  TabStripModel* strip = self.tabStrip;
  if (!strip || tabID == ClairTabIDNone) {
    return TabStripModel::kNoTab;
  }
  tabs::TabInterface* tab = tabs::TabHandle(static_cast<int32_t>(tabID)).Get();
  return tab ? strip->GetIndexOfTab(tab) : TabStripModel::kNoTab;
}

- (ClairPeeks*)peeks {
  return _browserWindow ? _browserWindow->peeks() : nullptr;
}

// The tab named by `tabID`, or null.
- (tabs::TabInterface*)tabWithID:(ClairTabID)tabID {
  const int index = [self indexOfTab:tabID];
  return index == TabStripModel::kNoTab ? nullptr
                                        : self.tabStrip->GetTabAtIndex(index);
}

- (id<ClairTab>)snapshotOf:(content::WebContents*)contents {
  ClairSpaceTabs* lists = _browserWindow ? _browserWindow->space_tabs() : nullptr;
  return lists ? lists->Snapshot(contents) : nil;
}

// --- Posting changes ---

- (void)postFlush {
  if (_flushPosted || !_browserWindow) {
    return;
  }
  _flushPosted = YES;
  ClairChromiumBrowser* __weak weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    [weakSelf flush];
  });
}

- (void)tabListChanged {
  ClairSpaceTabs* lists = _browserWindow ? _browserWindow->space_tabs() : nullptr;
  if (!lists) {
    return;
  }
  for (tabs::TabInterface* tab : _browserWindow->SpaceTabs()) {
    lists->ListChangedFor(tab);
  }
}

- (void)tabChanged:(content::WebContents*)contents {
  if (ClairSpaceTabs* lists =
          _browserWindow ? _browserWindow->space_tabs() : nullptr) {
    lists->TabChanged(contents);
  }
}

- (void)shownSpaceChangedFrom:(const std::string&)previousSpace {
  if (!_previousSpace) {
    _previousSpace = previousSpace;
  }
  [self postFlush];
}

- (void)activeTabChanged {
  [_historyMenu activeTabChanged];
  _activeTabChanged = YES;
  [self flush];
}

- (void)flush {
  _flushPosted = NO;
  // The tab lists first, so ClairUI knows a tab before it becomes active
  // (add-spaces D9).
  ClairSpaceTabs::FlushAll();
  id<ClairWindow> window = _window;
  if (!window || !_browserWindow) {
    _previousSpace.reset();
    _activeTabChanged = NO;
    return;
  }
  if (_previousSpace) {
    const std::string previous = *_previousSpace;
    _previousSpace.reset();
    if (previous != _browserWindow->shown_space()) {
      [window shownSpaceDidChange:self.shownSpaceID
                             from:previous.empty()
                                      ? nil
                                      : base::SysUTF8ToNSString(previous)];
    }
  }
  if (_activeTabChanged) {
    _activeTabChanged = NO;
    [window activeTabDidChange:self.activeTabID];
  }
}

// --- ClairBrowser: state ---

- (NSWindow<ClairWindowControls>*)window {
  return _browserWindow ? _browserWindow->ns_window() : nil;
}

- (ClairProfileKind)profileKind {
  Browser* browser = self.browser;
  if (!browser) {
    return ClairProfileKindRegular;
  }
  Profile* profile = browser->GetProfile();
  if (profile->IsGuestSession()) {
    return ClairProfileKindGuest;
  }
  return profile->IsOffTheRecord() ? ClairProfileKindIncognito
                                   : ClairProfileKindRegular;
}

- (ClairBrowserID)browserID {
  Browser* browser = self.browser;
  return browser ? browser->GetSessionID().id() : 0;
}

- (ClairSpaceID)shownSpaceID {
  return _browserWindow ? base::SysUTF8ToNSString(_browserWindow->shown_space())
                        : @"";
}

- (ClairTabID)activeTabID {
  TabStripModel* strip = self.tabStrip;
  content::WebContents* active = strip ? strip->GetActiveWebContents() : nullptr;
  return active ? TabIDOf(active) : ClairTabIDNone;
}

- (NSView*)pageViewForTab:(ClairTabID)tabID {
  const int index = [self indexOfTab:tabID];
  if (index == TabStripModel::kNoTab) {
    return nil;
  }
  return self.tabStrip->GetWebContentsAt(index)
      ->GetNativeView()
      .GetNativeNSView();
}

- (NSView*)devToolsView {
  TabStripModel* strip = self.tabStrip;
  content::WebContents* active = strip ? strip->GetActiveWebContents() : nullptr;
  if (!active) {
    return nil;
  }
  content::WebContents* devtools =
      DevToolsWindow::GetInTabWebContents(active, nullptr);
  return devtools ? devtools->GetNativeView().GetNativeNSView() : nil;
}

- (ClairDevToolsLayout)devToolsLayout {
  ClairDevToolsLayout layout = {ClairDevToolsDockSideNone, NSZeroRect, false};
  TabStripModel* strip = self.tabStrip;
  content::WebContents* active = strip ? strip->GetActiveWebContents() : nullptr;
  DevToolsContentsResizingStrategy strategy;
  if (!active || !DevToolsWindow::GetInTabWebContents(active, &strategy)) {
    return layout;
  }
  switch (strategy.dock_side()) {
    case devtools::DockSide::kRight:
      layout.dockSide = ClairDevToolsDockSideRight;
      break;
    case devtools::DockSide::kBottom:
      layout.dockSide = ClairDevToolsDockSideBottom;
      break;
    case devtools::DockSide::kLeft:
      layout.dockSide = ClairDevToolsDockSideLeft;
      break;
    case devtools::DockSide::kNone:
      layout.dockSide = ClairDevToolsDockSideNone;
      break;
  }
  const gfx::Rect& bounds = strategy.bounds();
  layout.pageBounds =
      NSMakeRect(bounds.x(), bounds.y(), bounds.width(), bounds.height());
  layout.hidesPage = strategy.hide_inspected_contents();
  return layout;
}

- (NSArray<id<ClairExtensionAction>>*)extensionActions {
  return _browserWindow && _browserWindow->extensions()
             ? _browserWindow->extensions()->Snapshot()
             : @[];
}

- (NSArray<id<ClairDownload>>*)downloads {
  return _browserWindow && _browserWindow->downloads()
             ? _browserWindow->downloads()->Snapshot()
             : @[];
}

- (ClairDownloadProgress)downloadProgress {
  return ClairDownloads::Progress();
}

// --- ClairBrowser: Spaces ---

- (void)showSpace:(ClairSpaceID)spaceID {
  if (_browserWindow && spaceID) {
    _browserWindow->ShowSpace(base::SysNSStringToUTF8(spaceID));
  }
}

// --- ClairBrowser: tabs ---

- (void)activateTab:(ClairTabID)tabID {
  const int index = [self indexOfTab:tabID];
  if (index != TabStripModel::kNoTab) {
    self.tabStrip->ActivateTabAt(
        index, TabStripUserGestureDetails(
                   TabStripUserGestureDetails::GestureType::kMouse));
  }
}

- (void)closeTab:(ClairTabID)tabID {
  // add-spaces D4: Clair picks the next tab before the close.
  if (tabs::TabInterface* tab = [self tabWithID:tabID]) {
    _browserWindow->CloseTab(tab);
  }
}

- (void)closeTabsBelowTab:(ClairTabID)tabID {
  // Below it in its Space, from its Peek (add-peek D8, add-spaces D5).
  if (tabs::TabInterface* tab = [self tabWithID:tabID]) {
    _browserWindow->CloseTabsBelow(tab);
  }
}

- (void)moveTab:(ClairTabID)tabID toIndex:(NSInteger)toIndex {
  // In the Space's list, with its Peek; no strip changes (add-spaces D2).
  tabs::TabInterface* tab = [self tabWithID:tabID];
  ClairSpaceTabs* lists = _browserWindow ? _browserWindow->space_tabs() : nullptr;
  if (tab && lists && toIndex >= 0) {
    lists->MoveTab(tab, static_cast<int>(
                            std::min<NSInteger>(toIndex, INT_MAX)));
  }
}

- (void)duplicateTab:(ClairTabID)tabID {
  const int index = [self indexOfTab:tabID];
  if (index != TabStripModel::kNoTab &&
      chrome::CanDuplicateTabAt(self.browser, index)) {
    chrome::DuplicateTabAt(self.browser, index);
  }
}

- (void)setMuted:(BOOL)muted forTab:(ClairTabID)tabID {
  const int index = [self indexOfTab:tabID];
  if (index != TabStripModel::kNoTab) {
    SetTabAudioMuted(self.tabStrip->GetWebContentsAt(index), muted,
                     TabMutedReason::kAudioIndicator, std::string());
  }
}

// --- ClairBrowser: Peek ---

- (void)closePeekOfTab:(ClairTabID)tabID {
  ClairPeeks* peeks = self.peeks;
  if (tabs::TabInterface* tab = peeks ? [self tabWithID:tabID] : nullptr) {
    peeks->Close(tab);
  }
}

- (void)expandPeekOfTab:(ClairTabID)tabID {
  ClairPeeks* peeks = self.peeks;
  if (tabs::TabInterface* tab = peeks ? [self tabWithID:tabID] : nullptr) {
    peeks->Expand(tab);
  }
}

// --- ClairBrowser: navigation ---

- (void)runCommand:(int)command {
  if (Browser* browser = self.browser) {
    chrome::ExecuteCommand(browser, command);
  }
}

- (void)goBack {
  [self runCommand:IDC_BACK];
}

- (void)goForward {
  [self runCommand:IDC_FORWARD];
}

- (void)reload {
  [self runCommand:IDC_RELOAD];
}

- (void)stop {
  [self runCommand:IDC_STOP];
}

- (void)openURL:(NSURL*)url disposition:(ClairOpenDisposition)disposition {
  Browser* browser = self.browser;
  GURL gurl = net::GURLWithNSURL(url);
  if (!browser || !gurl.is_valid()) {
    return;
  }
  NavigateParams params(browser, gurl, ui::PAGE_TRANSITION_TYPED);
  params.disposition = DispositionFor(disposition);
  params.window_action = NavigateParams::WindowAction::kShowWindow;
  Navigate(&params);
}

- (id<ClairAutocomplete>)startAutocompleteWithMode:(ClairCommandBarMode)mode
                                          delegate:
                                              (id<ClairAutocompleteDelegate>)
                                                  delegate {
  return [[ClairChromiumAutocomplete alloc] initWithBrowserWindow:_browserWindow
                                                             mode:mode
                                                         delegate:delegate];
}

- (id<ClairHistoryMenu>)startHistoryMenuWithDirection:
                            (ClairHistoryDirection)direction
                                             delegate:
                                                 (id<ClairHistoryMenuDelegate>)
                                                     delegate {
  [_historyMenu close];
  Browser* browser = self.browser;
  if (!browser) {
    return nil;
  }
  ClairChromiumHistoryMenu* menu =
      [[ClairChromiumHistoryMenu alloc] initWithBrowser:browser
                                              direction:direction
                                               delegate:delegate];
  if (!menu.hasPages) {
    [menu close];
    return nil;
  }
  _historyMenu = menu;
  return menu;
}

- (void)focusPage {
  TabStripModel* strip = self.tabStrip;
  if (content::WebContents* active =
          strip ? strip->GetActiveWebContents() : nullptr) {
    active->Focus();
  }
}

// --- ClairBrowser: find ---

- (void)findText:(NSString*)text forward:(BOOL)forward {
  if (_browserWindow && _browserWindow->find_bar()) {
    _browserWindow->find_bar()->FindFromField(base::SysNSStringToUTF16(text),
                                              forward);
  }
}

- (void)stopFinding {
  if (_browserWindow && _browserWindow->find_bar()) {
    _browserWindow->find_bar()->EndFromField();
  }
}

// --- ClairBrowser: site controls ---

- (void)showPageInfoAtAnchor:(ClairAnchorKind)kind
                   indicator:(ClairTabIndicators)indicator {
  TabStripModel* strip = self.tabStrip;
  content::WebContents* active = strip ? strip->GetActiveWebContents() : nullptr;
  if (!active) {
    return;
  }
  std::optional<ContentSettingsType> type;
  if (kind == ClairAnchorKindIndicator) {
    if (indicator & ClairTabIndicatorsCamera) {
      type = ContentSettingsType::MEDIASTREAM_CAMERA;
    } else if (indicator & ClairTabIndicatorsMicrophone) {
      type = ContentSettingsType::MEDIASTREAM_MIC;
    } else if (indicator & ClairTabIndicatorsLocation) {
      type = ContentSettingsType::GEOLOCATION;
    }
  }
  ShowPageInfoDialog(active, base::DoNothing(),
                     bubble_anchor_util::Anchor::kLocationBar, type);
}

// --- ClairBrowser: extensions ---

- (void)runExtensionAction:(NSString*)extensionID anchor:(ClairAnchorKind)anchor {
  if (_browserWindow && _browserWindow->extensions()) {
    _browserWindow->extensions()->Run(base::SysNSStringToUTF8(extensionID),
                                      anchor);
  }
}

- (void)setExtensionAction:(NSString*)extensionID pinned:(BOOL)pinned {
  if (_browserWindow && _browserWindow->extensions()) {
    _browserWindow->extensions()->SetPinned(
        base::SysNSStringToUTF8(extensionID), pinned);
  }
}

- (void)extensionPopupDidClose {
  if (_browserWindow && _browserWindow->extensions()) {
    _browserWindow->extensions()->PopupClosedByUser();
  }
}

- (NSMenu*)contextMenuForExtension:(NSString*)extensionID {
  if (_browserWindow && _browserWindow->extensions()) {
    return _browserWindow->extensions()->ContextMenu(
        base::SysNSStringToUTF8(extensionID));
  }
  return nil;
}

- (void)answerExtensionPrompt:(NSInteger)promptID accepted:(BOOL)accepted {
  if (_browserWindow && _browserWindow->extensions()) {
    _browserWindow->extensions()->AnswerPrompt(promptID, accepted);
  }
}

// --- ClairBrowser: downloads ---

- (ClairDownloads*)downloadsTracker {
  return _browserWindow ? _browserWindow->downloads() : nullptr;
}

- (void)openDownload:(NSString*)downloadID {
  if (ClairDownloads* downloads = self.downloadsTracker) {
    downloads->Open(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)showDownloadInFinder:(NSString*)downloadID {
  if (ClairDownloads* downloads = self.downloadsTracker) {
    downloads->ShowInFinder(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)cancelDownload:(NSString*)downloadID {
  if (ClairDownloads* downloads = self.downloadsTracker) {
    downloads->Cancel(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)resumeDownload:(NSString*)downloadID {
  if (ClairDownloads* downloads = self.downloadsTracker) {
    downloads->Resume(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)keepDownload:(NSString*)downloadID {
  if (ClairDownloads* downloads = self.downloadsTracker) {
    downloads->Keep(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)discardDownload:(NSString*)downloadID {
  if (ClairDownloads* downloads = self.downloadsTracker) {
    downloads->Discard(base::SysNSStringToUTF8(downloadID));
  }
}

- (void)markDownloadsSeen {
  if (ClairDownloads* downloads = self.downloadsTracker) {
    downloads->MarkSeen();
  }
}

// --- ClairBrowser: infobars ---

- (void)infobar:(NSInteger)infobarID
          ofTab:(ClairTabID)tabID
      didChoose:(ClairInfobarAction)action {
  const int index = [self indexOfTab:tabID];
  if (index == TabStripModel::kNoTab) {
    return;
  }
  auto* manager = infobars::ContentInfoBarManager::FromWebContents(
      self.tabStrip->GetWebContentsAt(index));
  if (!manager) {
    return;
  }
  infobars::InfoBar* infobar = nullptr;
  for (infobars::InfoBar* candidate : manager->infobars()) {
    if (InfobarIDOf(candidate) == infobarID) {
      infobar = candidate;
    }
  }
  ConfirmInfoBarDelegate* delegate =
      infobar ? infobar->delegate()->AsConfirmInfoBarDelegate() : nullptr;
  if (!delegate) {
    return;
  }
  bool remove = false;
  switch (action) {
    case ClairInfobarActionOK:
      remove = delegate->Accept();
      break;
    case ClairInfobarActionCancel:
      remove = delegate->Cancel();
      break;
    case ClairInfobarActionLink:
      remove = delegate->LinkClicked(WindowOpenDisposition::NEW_FOREGROUND_TAB);
      break;
    case ClairInfobarActionDismiss:
      delegate->InfoBarDismissed();
      remove = true;
      break;
  }
  if (remove) {
    infobar->RemoveSelf();
  }
}

// --- ClairBrowser: the window ---

- (void)requestClose {
  if (_browserWindow) {
    _browserWindow->WindowCloseRequested();
  }
}

@end
