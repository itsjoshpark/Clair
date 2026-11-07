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

#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "base/callback_list.h"
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
@protocol ClairWindow;

class Browser;
class ClairBrowserWindow;
class ClairDownloads;
class ClairExtensions;

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
  // Owned by the browser's FindBarController once created.
  raw_ptr<ClairFindBar> find_bar_ = nullptr;
  base::CallbackListSubscription zoom_subscription_;
  // The show state session restore asked for, applied when first shown.
  ui::mojom::WindowShowState initial_show_state_ =
      ui::mojom::WindowShowState::kDefault;
  // The frame outside full screen, minimized and zoomed states.
  gfx::Rect restored_bounds_;
  bool detached_ = false;
  base::WeakPtrFactory<ClairBrowserWindow> weak_factory_{this};
};

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_BROWSER_WINDOW_H_
