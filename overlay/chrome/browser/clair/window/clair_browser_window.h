// Copyright 2026 The Clair Authors
// This Source Code Form is subject to the terms of the Mozilla Public License,
// v. 2.0. If a copy of the MPL was not distributed with this file, You can
// obtain one at https://mozilla.org/MPL/2.0/.
//
// Adapted in part from Crest's CrestBrowserWindow (pauljoda/Crest, MPL-2.0),
// which adapts Mori's (MIT, see CREDITS.md), and from Chromium's own
// WebUIBrowserWindow (BSD-3-Clause).

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_BROWSER_WINDOW_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_BROWSER_WINDOW_H_

#include <map>
#include <memory>
#include <optional>
#include <set>
#include <string>
#include <vector>

#include "base/callback_list.h"
#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/observer_list.h"
#include "base/timer/timer.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/bubble_anchor_util.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_context.h"
#include "chrome/browser/ui/find_bar/find_bar.h"
#include "chrome/browser/ui/location_bar/location_bar.h"
#include "chrome/browser/ui/status_bubble.h"
#include "components/tabs/public/tab_interface.h"
#include "components/web_modal/web_contents_modal_dialog_host.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/range/range.h"

#if !defined(__OBJC__)
#error "clair_browser_window.h holds Objective-C members; include it from .mm files"
#endif

@class ClairChromiumBrowser;
@class ClairNativeWindow;
@class NSEvent;
@class NSImage;
@class NSWindow;
@protocol ClairWindow;

class Browser;
class ClairBrowserWindow;
class ClairDownloads;
class SkBitmap;
class ClairExtensions;
class ClairPeeks;
class ClairSpaceTabs;
class GURL;

namespace autofill {
class AutofillBubbleHandler;
}  // namespace autofill

// The location bar a native window gives Chromium: there is none to draw, but
// Chromium dereferences it on every tab switch. Focusing it opens the command
// bar. It has no chip controller, so permission requests use the bubble.
class ClairLocationBar : public LocationBar {
 public:
  explicit ClairLocationBar(ClairBrowserWindow* window);
  ~ClairLocationBar() override;

  // LocationBar:
  void FocusLocation(bool is_user_initiated, bool clear_focus_if_failed) override;
  void FocusSearch() override;
  void AnnounceAlert(const std::u16string& announcement) override;
  void UpdateFocusBehavior(bool toolbar_visible) override;
  void UpdateContentSettingsIcons() override;
  void SaveStateToContents(content::WebContents* contents) override;
  void Revert() override;
  OmniboxView* GetOmniboxView() override;
  OmniboxPopupView* GetOmniboxPopupView() override;
  OmniboxController* GetOmniboxController() override;
  bool ShouldCloseOmniboxPopup(ui::MouseEvent* event) override;
  content::WebContents* GetWebContents() override;
  LocationBarModel* GetLocationBarModel() override;
  std::optional<bubble_anchor_util::AnchorConfiguration> GetChipAnchor() override;
  ChipController* GetChipController() override;
  void OnChanged() override;
  void UpdateWithoutTabRestore() override;
  ui::TrackedElement* GetAnchorOrNull() override;
  BrowserWindowInterface* GetBrowser() override;
  Profile* GetProfile() override;
  bool IsInitialized() const override;
  bool IsVisible() const override;
  bool IsDrawn() const override;
  bool IsFullscreen() const override;
  bool IsEditingOrEmpty() const override;
  bool IsMouseHovered() const override;
  bool IsFocusWithin() const override;
  void InvalidateLayout() override;
  gfx::Rect Bounds() const override;
  gfx::Rect BoundsInScreen() const override;
  gfx::Size MinimumSize() const override;
  gfx::Size PreferredSize() const override;
  void Update(content::WebContents* contents) override;
  void ResetTabState(content::WebContents* contents) override;
  bool HasSecurityStateChanged() override;
  LocationBarTesting* GetLocationBarForTesting() override;

 private:
  const raw_ptr<ClairBrowserWindow> window_;
};

// Chromium's find bar for a native window (D8). The find field is ClairUI's;
// this keeps the text and reports results to it.
class ClairFindBar : public FindBar {
 public:
  explicit ClairFindBar(ClairBrowserWindow* window);
  ~ClairFindBar() override;

  // FindBar:
  FindBarController* GetFindBarController() const override;
  void SetFindBarController(FindBarController* find_bar_controller) override;
  void Show(bool animate, bool focus) override;
  void Hide(bool animate) override;
  void SetFocusAndSelection() override;
  void ClearResults(const find_in_page::FindNotificationDetails& results) override;
  void StopAnimation() override;
  void MoveWindowIfNecessary() override;
  void SetFindTextAndSelectedRange(const std::u16string& find_text,
                                   const gfx::Range& selected_range) override;
  std::u16string_view GetFindText() const override;
  gfx::Range GetSelectedRange() const override;
  void UpdateUIForFindResult(const find_in_page::FindNotificationDetails& result,
                             const std::u16string& find_text) override;
  void AudibleAlert() override;
  bool IsFindBarVisible() const override;
  void RestoreSavedFocus() override;
  bool HasGlobalFindPasteboard() const override;
  void UpdateFindBarForChangedWebContents() override;
  bool CanPopulateFromSelectedText() override;
  const FindBarTesting* GetFindBarTesting() const override;
  bool HasFocus() const override;
  void CloseOverlappingBubbles() override;
  views::Widget* GetHostWidget() override;

  // What the user typed in ClairUI's field: finds it, or the next match.
  void FindFromField(const std::u16string& text, bool forward);
  // Esc in ClairUI's field.
  void EndFromField();

 private:
  const raw_ptr<ClairBrowserWindow> window_;
  raw_ptr<FindBarController> controller_ = nullptr;
  std::u16string text_;
  gfx::Range selected_range_;
  bool visible_ = false;
};

// Page full screen in a native window (D6). A page's request shows the page
// alone in macOS full screen; Chromium hears every full-screen transition of
// the window, whoever started it.
class ClairExclusiveAccessContext : public ExclusiveAccessContext {
 public:
  explicit ClairExclusiveAccessContext(ClairBrowserWindow* window);
  ~ClairExclusiveAccessContext() override;

  // ExclusiveAccessContext:
  Profile* GetProfile() override;
  bool IsFullscreen() const override;
  void EnterFullscreen(const url::Origin& origin,
                       ExclusiveAccessBubbleType bubble_type,
                       FullscreenTabParams fullscreen_tab_params) override;
  void ExitFullscreen() override;
  void UpdateExclusiveAccessBubble(
      const ExclusiveAccessBubbleParams& params,
      ExclusiveAccessBubbleHideCallback first_hide_callback) override;
  bool IsExclusiveAccessBubbleDisplayed() const override;
  void OnExclusiveAccessUserInput() override;
  content::WebContents* GetWebContentsForExclusiveAccess() override;
  bool CanUserEnterFullscreen() const override;
  bool CanUserExitFullscreen() const override;
  void UpdateUIForTabFullscreen() override;

  // The window finished entering or leaving macOS full screen.
  void WindowFullscreenChanged(bool entered);

  bool page_fullscreen() const { return page_fullscreen_; }

  // Esc arrived while the window was still animating into full screen, when
  // AppKit ignores a request to leave it; full screen ends once the window
  // is in. Returns whether the key was taken.
  bool DeferExitWhileEntering(NSEvent* event);

 private:
  void SetPageFullscreen(bool fullscreen);
  void HideNotice(ExclusiveAccessBubbleHideReason reason);

  const raw_ptr<ClairBrowserWindow> window_;
  bool page_fullscreen_ = false;
  // Whether entering page full screen also entered macOS full screen, so
  // leaving it should leave macOS full screen too.
  bool entered_window_fullscreen_ = false;
  // Between asking the window for full screen and its getting there.
  bool entering_window_fullscreen_ = false;
  bool exit_when_entered_ = false;
  bool notice_visible_ = false;
  ExclusiveAccessBubbleHideCallback notice_hide_callback_;
  base::OneShotTimer notice_timer_;
};

// Hosts Chromium's tab-modal dialogs (JavaScript dialogs, HTTP auth, print
// preview) over the card.
class ClairModalDialogHost : public web_modal::WebContentsModalDialogHost {
 public:
  explicit ClairModalDialogHost(ClairBrowserWindow* window);
  ~ClairModalDialogHost() override;

  // WebContentsModalDialogHost:
  gfx::NativeView GetHostView() const override;
  gfx::Point GetDialogPosition(const gfx::Size& size) override;
  gfx::Size GetMaximumDialogSize() override;
  void AddObserver(web_modal::ModalDialogHostObserver* observer) override;
  void RemoveObserver(web_modal::ModalDialogHostObserver* observer) override;

  // The card's size changed.
  void NotifyPositionRequiresUpdate() override;

 private:
  gfx::Rect CardRect() const;

  const raw_ptr<ClairBrowserWindow> window_;
  base::ObserverList<web_modal::ModalDialogHostObserver> observers_;
};

// Forwards link-hover URLs to the status capsule (D8).
class ClairStatusBubble : public StatusBubble {
 public:
  explicit ClairStatusBubble(ClairBrowserWindow* window);
  ~ClairStatusBubble() override;

  // StatusBubble:
  void SetStatus(const std::u16string& status) override;
  void SetURL(const GURL& url) override;
  void Hide() override;
  void MouseMoved(bool left_content) override;

 private:
  void Update();

  const raw_ptr<ClairBrowserWindow> window_;
  std::u16string status_;
  std::u16string url_;
};

// share-tabs-across-windows D1, D2: how a window takes a tab another window
// holds.
struct ClairTakeOptions {
  ClairTakeOptions();
  ClairTakeOptions(ClairTakeOptions&&);
  ClairTakeOptions& operator=(ClairTakeOptions&&);
  ~ClairTakeOptions();

  // Whether the tab waits for its page's copy before it moves, when the
  // other window shows it; otherwise it moves at once, and the still's image
  // follows if the copy comes.
  bool wait_for_copy = true;
  // Clair's choice of the next tab, which sets no came-from (add-spaces D4).
  bool choosing = false;
  // Runs once the tab is active here, or at once when there's nothing to
  // take.
  base::OnceClosure then;
};

// Chromium's BrowserWindow for a native window (D1). Chromium keeps the
// browser, its tabs, session restore, commands and extensions; ClairUI draws
// the window.
//
// Each BrowserWindow method is one of:
// - forwarded to ClairUI (tabs, toolbar state, find, toasts, full screen);
// - answered from the NSWindow (bounds, state, activation);
// - handled in this overlay (the helpers above, DevTools, extensions,
//   downloads); or
// - one of D9's unavailable features, which does nothing and logs once.
class ClairBrowserWindow : public BrowserWindow {
 public:
  explicit ClairBrowserWindow(Browser* browser);
  ClairBrowserWindow(const ClairBrowserWindow&) = delete;
  ClairBrowserWindow& operator=(const ClairBrowserWindow&) = delete;
  ~ClairBrowserWindow() override;

  // The native window of `browser`, or null.
  static ClairBrowserWindow* FromBrowser(const BrowserWindowInterface* browser);
  // The native window showing `contents`, or null.
  static ClairBrowserWindow* FromWebContents(content::WebContents* contents);
  // Every native window.
  static std::vector<ClairBrowserWindow*> All();

  Browser* browser() const { return browser_; }
  base::WeakPtr<ClairBrowserWindow> GetWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

  ClairNativeWindow* ns_window() const { return ns_window_; }
  ClairChromiumBrowser* bridge() const { return bridge_; }
  // ClairUI's window; nil once the browser closed.
  id<ClairWindow> clair_window() const { return clair_window_; }

  ClairFindBar* find_bar() const { return find_bar_; }
  ClairExtensions* extensions() const { return extensions_.get(); }
  ClairDownloads* downloads() const { return downloads_.get(); }
  // The window's Peeks (add-peek design D1); null once the window is going.
  ClairPeeks* peeks() const { return peeks_.get(); }
  // The tab lists of the window's profile (add-spaces design D2).
  ClairSpaceTabs* space_tabs() const { return space_tabs_; }

  // --- Spaces (add-spaces design D3, D4, D5; share-tabs-across-windows
  // design D1 to D4) ---
  // The Space the window shows. Its active tab always belongs to it, except
  // its placeholder while it shows a still.
  const std::string& shown_space() const { return shown_space_; }
  // Shows `space`: activates the tab last active in it here unless another
  // window shows it, or else the Space's most recently active row that no
  // window shows, taking it from the window that holds it, or else opens a
  // new tab page in it with the command bar. Ignored for an unknown Space and
  // in incognito and guest windows.
  // A Space of another profile is shown by the window's group, which swaps to
  // its member for that profile (add-profiles D3). With `again`, a member
  // the group swaps in shows the Space even if it showed it already, as its
  // active tab may be its placeholder.
  void ShowSpace(const std::string& space, bool again = false);
  // The tabs of the shown Space, in its order, whichever window of the
  // profile holds them: with Peeks, or only the rows the sidebar lists. An
  // incognito or guest window's are its own.
  std::vector<tabs::TabInterface*> SpaceTabs() const;
  std::vector<tabs::TabInterface*> Rows() const;
  // Whether `tab` is the row the window shows: the active tab, or the parent
  // of the active Peek. Never while the window shows a still.
  bool IsActiveRow(const tabs::TabInterface* tab) const;
  // The row the window shows or highlights: the active row, or the still's
  // tab; null when there's none.
  tabs::TabInterface* HighlightedRow() const;
  // D4: before the active row `row` leaves the Space, shows the row the user
  // came from, if it's still listed, or else the row above, or else the row
  // below, taking it from another window if need be. Returns false, changing
  // nothing, when there's none.
  // With `then`, a tab another window shows waits for its page's copy, and
  // `then` moves into the take and runs once the tab is here; without, the
  // tab moves at once.
  bool ShowNextRow(tabs::TabInterface* row, base::OnceClosure* then = nullptr);
  // D4: closes `tab`, in whichever window holds it, with its leave-page
  // confirmation, first showing the next tab if it's the active one. A page
  // with unload handlers is asked first, and the next tab shows once it
  // agrees.
  void CloseTab(tabs::TabInterface* tab);
  // D4: `contents` answered a close. If Clair started it and the page agreed,
  // shows the next row before Chromium closes the tab.
  void BeforeUnloadFired(content::WebContents* contents, bool proceed);
  // Closes the rows below `tab` in its Space, from its Peek, in whichever
  // window holds each.
  void CloseTabsBelow(tabs::TabInterface* tab);
  // Activates `row`, or its Peek if it has one, taking it from another window
  // if need be.
  void ActivateRow(tabs::TabInterface* row,
                   ClairTakeOptions options = ClairTakeOptions());
  // Activates `tab` exactly, taking it from another window if need be.
  void ActivateTab(tabs::TabInterface* tab,
                   ClairTakeOptions options = ClairTakeOptions());
  // Opens a new tab page in the shown Space, optionally with the command bar.
  void OpenNewTabPage(bool show_command_bar);
  // Opens `url` in a new foreground tab of the shown Space, or a new tab page
  // with the command bar when it's empty.
  void OpenInShownSpace(const GURL& url);

  // --- Window groups (add-profiles D3 to D6, D8, D13) ---
  // Whether the window is a member its group has ordered out.
  bool IsHiddenMember() const;
  // The group is about to swap this member in from a window showing
  // `previous_space`: ClairUI hears that Space as the one shown before.
  void BeginSwapIn(const std::string& previous_space);
  // Orders the window in above `above` (or front), makes it key when
  // `make_key`, and shows its pages.
  void Reveal(NSWindow* above, bool make_key);
  // The window comes in on the active macOS Space, whichever it was on when
  // ordered out, until the current task is done: ordering it in mustn't
  // switch macOS Spaces (add-profiles D3, D4).
  void JoinActiveSpace();
  // Hides its pages and, with `order_out`, orders the window out. A still it
  // showed ends, its placeholder staying active without one, and a take it
  // waits for is dropped (D5).
  void Conceal(bool order_out);
  // D4: the window covers its group's full-screen window: no corners or
  // window controls.
  void SetCovering(bool covering);
  // The window's NSWindow, or its group's full-screen one while it covers it,
  // which full-screen requests go to (D4).
  NSWindow* FullscreenNSWindow() const;
  // D5: moves every tab, the placeholder and `except` left out, to `target`,
  // a window of the same profile. Returns whether it moved any.
  bool HandTabsTo(ClairBrowserWindow* target, tabs::TabInterface* except);
  // Closes `tab` at once, without picking a next tab.
  void CloseTabWithoutChoosing(tabs::TabInterface* tab);
  // Whether a tab's page would ask before the window closes.
  bool NeedsBeforeUnload() const;
  // Whether the window holds a tab other than its placeholder.
  bool HasRealTabs() const;
  // The URLs of its pages, new tab pages and the placeholder left out.
  std::vector<GURL> PageURLs() const;
  // D6: the group named by the first of its tabs restored with a group tag,
  // or empty.
  std::string RestoredGroupTag() const;
  // D6: shows `space` after session restore, on the restored selected tab
  // when it's in the Space, or else as ShowSpace() picks.
  void ShowRestoredSpace(const std::string& space);
  // D6, D7: shows `space`, a Space of the window's profile, on a new tab of
  // `url`, or a new tab page with the command bar when it's empty.
  void ShowSpaceOnNewTab(const std::string& space, const GURL& url);
  // add-profiles D9: the active tab moved to another Space of the profile;
  // the window shows that Space, the tab staying active.
  void FollowActiveTab();
  // add-profiles D9: drops a take waiting for `tab`'s page copy.
  void DropPendingTakeOf(const tabs::TabInterface* tab);
  // D5: runs a tab command over the rows of the shown Space. Returns whether
  // it ran; otherwise Chromium runs it.
  bool ExecuteTabCommand(int command);

  // --- Tabs shared across windows (share-tabs-across-windows D1, D2) ---
  // The window holding `tab`, or null.
  static ClairBrowserWindow* HolderOf(const tabs::TabInterface* tab);
  // Whether another window of the profile shows `row`.
  bool IsShownElsewhere(const tabs::TabInterface* row) const;
  // D1: moves `tab` and its Peek here from the window that holds them and
  // activates `tab`. The other window keeps a still if it showed them.
  void Take(tabs::TabInterface* tab,
            ClairTakeOptions options = ClairTakeOptions());
  // D2: the tab the window shows a still of, or a null handle.
  tabs::TabHandle still_tab() const { return still_tab_; }
  NSImage* still_image() const { return still_image_; }
  // D2: the still's tab closed: the placeholder becomes a new tab page of the
  // shown Space, with the command bar.
  void StillTabClosed();
  ClairExclusiveAccessContext* exclusive_access_context() {
    return &exclusive_access_context_;
  }
  ClairModalDialogHost* modal_dialog_host() { return &modal_dialog_host_; }

  // Events from the NSWindow.
  void WindowDidBecomeKey();
  void WindowDidResignKey();
  void WindowGeometryChanged();
  // Esc during page full screen, from the window rather than the page: it
  // ends full screen whatever has the keyboard, as in Chromium's window.
  // Returns whether the event was used.
  bool HandleExclusiveAccessKey(NSEvent* event);
  void WindowFullscreenChanged(bool entered);
  // The close button: Chromium's close flow, which may keep the window open.
  void WindowCloseRequested();

  // The find bar is going away with its FindBarController.
  void ForgetFindBar();

  // The active tab's docked DevTools changed (D5).
  void UpdateDevTools();

  // The link under the pointer, or an empty URL to hide the status (D8).
  void SetStatusURL(const GURL& url);

  // Shows a toast in the card (D8).
  void ShowToast(const std::u16string& text);

  // Where a bubble for the site controls attaches, in screen coordinates.
  gfx::Rect SiteControlsAnchorInScreen() const;

  // BrowserWindow / ui::BaseWindow:
  bool IsActive() const override;
  bool IsMaximized() const override;
  bool IsMinimized() const override;
  bool IsFullscreen() const override;
  gfx::NativeWindow GetNativeWindow() const override;
  gfx::Rect GetRestoredBounds() const override;
  ui::mojom::WindowShowState GetRestoredState() const override;
  gfx::Rect GetBounds() const override;
  void Show() override;
  void Hide() override;
  bool IsVisible() const override;
  void ShowInactive() override;
  void Close() override;
  void Activate() override;
  void Deactivate() override;
  void Maximize() override;
  void Minimize() override;
  void Restore() override;
  void SetBounds(const gfx::Rect& bounds) override;
  void FlashFrame(bool flash) override;
  ui::ZOrderLevel GetZOrderLevel() const override;
  void SetZOrderLevel(ui::ZOrderLevel order) override;
  bool IsOnCurrentWorkspace() const override;
  bool IsVisibleOnScreen() const override;
  void SetTopControlsShownRatio(content::WebContents* web_contents,
                                float ratio) override;
  bool DoBrowserControlsShrinkRendererSize(
      const content::WebContents* contents) const override;
  ui::NativeTheme* GetNativeTheme() override;
  const ui::ThemeProvider* GetThemeProvider() const override;
  const ui::ColorProvider* GetColorProvider() const override;
  int GetTopControlsHeight() const override;
  void SetTopControlsGestureScrollInProgress(bool in_progress) override;
  std::vector<StatusBubble*> GetStatusBubbles() override;
  void UpdateTitleBar() override;
  void UpdateLoadingAnimations(bool is_visible) override;
  void OnActiveTabChanged(content::WebContents* old_contents,
                          content::WebContents* new_contents,
                          int index,
                          int reason) override;
  void OnTabDetached(content::WebContents* contents, bool was_active) override;
  gfx::Size GetContentsSize() const override;
  void SetContentsSize(const gfx::Size& size) override;
  autofill::AutofillBubbleHandler* GetAutofillBubbleHandler() override;
  LocationBar* GetLocationBar() const override;
  ui::AcceleratorProvider* GetAcceleratorProvider() override;
  PinnedToolbarActions* GetPinnedToolbarActions() override;
  void SetFocusToLocationBar(bool is_user_initiated) override;
  void UpdateReloadStopState(bool is_loading, bool force) override;
  void UpdateToolbar(content::WebContents* contents) override;
  bool UpdateToolbarSecurityState() override;
  void UpdateCustomTabBarVisibility(bool visible, bool animate) override;
  void ResetToolbarTabState(content::WebContents* contents) override;
  void FocusToolbar() override;
  void ToolbarSizeChanged(bool is_animating) override;
  void TabDraggingStatusChanged(bool is_dragging) override;
  void LinkOpeningFromGesture(WindowOpenDisposition disposition) override;
  void FocusAppMenu() override;
  bool IsTabStripEditable() const override;
  void DisableTabStripEditingForTesting() override;
  bool IsToolbarVisible() const override;
  bool IsToolbarShowing() const override;
  bool IsLocationBarVisible() const override;
  void ShowUpdateChromeDialog() override;
  void ShowIntentPickerBubble(
      std::vector<apps::IntentPickerAppInfo> app_info,
      bool show_stay_in_chrome,
      bool show_remember_selection,
      apps::IntentPickerBubbleType bubble_type,
      const std::optional<url::Origin>& initiating_origin,
      IntentPickerResponse callback) override;
  void ShowBookmarkBubble(const GURL& url, bool already_bookmarked) override;
  ShowTranslateBubbleResult ShowTranslateBubble(
      content::WebContents* contents,
      translate::TranslateStep step,
      const std::string& source_language,
      const std::string& target_language,
      translate::TranslateErrors error_type,
      bool is_user_gesture) override;
  DownloadBubbleUIController* GetDownloadBubbleUIController() override;
  void ConfirmBrowserCloseWithPendingDownloads(
      int download_count,
      DownloadCloseType dialog_type,
      base::OnceCallback<void(bool)> callback) override;
  void ShowAppMenu() override;
  void PreHandleDragUpdate(const content::DropData& drop_data,
                           const gfx::PointF& point) override;
  void PreHandleDragExit() override;
  void HandleDragEnded() override;
  content::KeyboardEventProcessingResult PreHandleKeyboardEvent(
      const input::NativeWebKeyboardEvent& event) override;
  bool HandleKeyboardEvent(const input::NativeWebKeyboardEvent& event) override;
  std::unique_ptr<FindBar> CreateFindBar() override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHost()
      override;
  web_modal::WebContentsModalDialogHost* GetWebContentsModalDialogHostFor(
      content::WebContents* web_contents) override;
  void ShowAvatarBubbleFromAvatarButton(bool is_source_accelerator) override;
  void MaybeShowProfileSwitchIPH() override;
  void MaybeShowSupervisedUserProfileSignInIPH() override;
  void ShowHatsDialog(
      const std::string& site_id,
      const std::optional<std::string>& hats_histogram_name,
      const std::optional<uint64_t> hats_survey_ukm_id,
      base::OnceClosure success_callback,
      base::OnceClosure failure_callback,
      const SurveyBitsData& product_specific_bits_data,
      const SurveyStringData& product_specific_string_data) override;
  ExclusiveAccessContext* GetExclusiveAccessContext() override;
  std::string GetWorkspace() const override;
  bool IsVisibleOnAllWorkspaces() const override;
  void ShowEmojiPanel() override;
  std::unique_ptr<content::EyeDropper> OpenEyeDropper(
      content::RenderFrameHost* frame,
      content::EyeDropperListener* listener) override;
  void ShowCaretBrowsingDialog() override;
  void CreateTabSearchBubble() override;
  void CloseTabSearchBubble() override;
  void ShowIncognitoClearBrowsingDataDialog() override;
  void ShowIncognitoHistoryDisclaimerDialog() override;
  bool IsUnframedModeEnabled() const override;
  bool GetCanResize() override;
  ui::mojom::WindowShowState GetWindowShowState() const override;
  void ShowChromeLabs() override;
  BrowserView* AsBrowserView() override;

 protected:
  // BrowserWindow:
  void DeleteBrowserWindow() override;

 private:
  // The zoom of the active tab changed.
  void ZoomChanged(bool can_show_bubble);
  // Tells ClairUI the browser closed and lets go of it, once.
  void DetachFromClairUI();
  // D3: the window now shows `space`; ClairUI hears of it with the next push.
  void SetShownSpace(const std::string& space);
  // share-tabs-across-windows D3: shows `row` as Clair's choice of the next
  // tab, which sets no came-from.
  // With `then`, as ShowNextRow().
  void ChooseRow(tabs::TabInterface* row, base::OnceClosure* then);
  // add-profiles D13: the active row `row` closes with no other row to show:
  // a new tab page with the command bar takes its place in the Space, or,
  // when `row` is itself a new tab page and the Space's only row, the window
  // closes as the user's close does. Returns whether the window closes.
  bool KeepEmptiedSpace(tabs::TabInterface* row);
  // Closes `handle`'s tab, with its leave-page confirmation.
  void CloseTabNow(tabs::TabHandle handle);
  // D1: whether `tab` is one this window can take: another regular window's
  // of the same profile, and not a placeholder.
  bool CanTake(const tabs::TabInterface* tab) const;
  // D1, D2: moves the tab named by `handle` here once its page's copy has
  // come (empty without one), leaving a still in the window that showed it.
  // `generation` tells a take from one cancelled since.
  void FinishTake(tabs::TabHandle handle,
                  int generation,
                  ClairTakeOptions options,
                  const SkBitmap& copy);
  // D1: drops the take waiting for its page's copy, if any, and runs what
  // was to run after it.
  void CancelPendingTake();
  // D2: the copy of the still's page came after the tab left.
  void SetStillImage(tabs::TabHandle handle, const SkBitmap& copy);
  NSImage* StillImageFrom(const SkBitmap& copy) const;
  // D2: copies `row`'s page, waiting at most 250 ms, and hands `done` the
  // copy, or an empty bitmap.
  void CopyPage(tabs::TabInterface* row,
                base::OnceCallback<void(const SkBitmap&)> done);
  // D1: moves `row` and its Peek from `from` to this window's strip, keeping
  // their place in the Space's list. Activates nothing.
  void MoveFamilyHere(ClairBrowserWindow* from, tabs::TabInterface* row);
  // D2: starts a still of `row`, which another window is taking, with its
  // page's copy (empty without one), and activates a placeholder.
  void BeginStill(tabs::TabInterface* row, const SkBitmap& copy);
  // D2: ends the still, closing the placeholder unless it became a tab.
  void EndStill();
  tabs::TabInterface* placeholder() const;
  // The pages the card shows while `active` is the active tab: it and its
  // Peek or parent (add-peek D4).
  std::set<content::WebContents*> PagesShownWith(
      content::WebContents* active) const;

  const raw_ptr<Browser> browser_;
  ClairNativeWindow* __strong ns_window_ = nil;
  ClairChromiumBrowser* __strong bridge_ = nil;
  id<ClairWindow> __strong clair_window_ = nil;
  ClairLocationBar location_bar_;
  ClairModalDialogHost modal_dialog_host_;
  ClairExclusiveAccessContext exclusive_access_context_;
  ClairStatusBubble status_bubble_;
  std::unique_ptr<autofill::AutofillBubbleHandler> autofill_bubble_handler_;
  std::unique_ptr<ClairExtensions> extensions_;
  std::unique_ptr<ClairDownloads> downloads_;
  std::unique_ptr<ClairPeeks> peeks_;
  // Owned by the profile.
  raw_ptr<ClairSpaceTabs> space_tabs_ = nullptr;
  // add-spaces D3: the Space the window shows, and the tab last active in
  // each Space here.
  std::string shown_space_;
  std::map<std::string, tabs::TabHandle> last_active_;
  // D4: the row the user selected the active tab from, or null.
  tabs::TabHandle came_from_;
  // While Clair activates the next tab before a close, which sets no
  // came-from.
  bool choosing_next_ = false;
  // share-tabs-across-windows D2: the tab the window shows a still of, its
  // page's copy and the placeholder under it.
  tabs::TabHandle still_tab_;
  NSImage* __strong still_image_ = nil;
  tabs::TabHandle placeholder_;
  // D1: the tab waiting for its page's copy before it moves here, what joined
  // that take, and a count that tells a take from one cancelled since.
  tabs::TabHandle taking_;
  std::vector<base::OnceClosure> pending_take_thens_;
  int take_generation_ = 0;
  // D3: while a close another window started chooses the next tab, which
  // takes none another window shows; and the same for a close waiting on its
  // page's answer.
  bool closing_for_another_window_ = false;
  bool pending_close_for_another_window_ = false;
  // D4: the active row Clair is closing, while its page is asked; or null.
  tabs::TabHandle pending_close_;
  // Owned by the browser's FindBarController once created.
  raw_ptr<ClairFindBar> find_bar_ = nullptr;
  base::CallbackListSubscription zoom_subscription_;
  // The real Show(), once session restore has finished and the window is its
  // group's shown member.
  void ShowNow();
  // add-profiles D8: the regular window opened in a profile no Space uses.
  bool hands_over_ = false;
  // The show state session restore asked for, applied when first shown.
  ui::mojom::WindowShowState initial_show_state_ =
      ui::mojom::WindowShowState::kDefault;
  // The frame outside full screen, minimized and zoomed states.
  gfx::Rect restored_bounds_;
  bool detached_ = false;
  base::WeakPtrFactory<ClairBrowserWindow> weak_factory_{this};
};

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_BROWSER_WINDOW_H_
