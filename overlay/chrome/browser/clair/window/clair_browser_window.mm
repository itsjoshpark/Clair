// Copyright 2026 The Clair Authors
// This Source Code Form is subject to the terms of the Mozilla Public License,
// v. 2.0. If a copy of the MPL was not distributed with this file, You can
// obtain one at https://mozilla.org/MPL/2.0/.
//
// Adapted in part from Crest's CrestBrowserWindow (pauljoda/Crest, MPL-2.0),
// which adapts Mori's (MIT, see CREDITS.md), and from Chromium's own
// WebUIBrowserWindow and BrowserNativeWidgetMac (BSD-3-Clause).

#include "chrome/browser/clair/window/clair_browser_window.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <map>
#include <set>
#include <string>
#include <type_traits>
#include <vector>

#include "base/auto_reset.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "base/logging.h"
#include "base/memory/ref_counted.h"
#include "base/no_destructor.h"
#include "base/task/sequenced_task_runner.h"
#include "base/time/time.h"
#include "base/strings/stringprintf.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#import "chrome/browser/clair/ClairHost.h"
#include "chrome/browser/clair/clair_native_layer.h"
#include "chrome/browser/clair/clair_space_store.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#import "chrome/browser/clair/window/clair_browser_bridge.h"
#include "chrome/browser/clair/window/clair_downloads.h"
#include "chrome/browser/clair/window/clair_extensions.h"
#import "chrome/browser/clair/window/clair_native_window.h"
#include "chrome/browser/clair/window/clair_peeks.h"
#include "chrome/browser/clair/window/clair_window_hooks.h"
#include "chrome/app/chrome_command_ids.h"
#include "chrome/browser/global_keyboard_shortcuts_mac.h"
#include "chrome/browser/lifetime/browser_shutdown.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/themes/theme_service.h"
#include "chrome/browser/ui/autofill/autofill_bubble_handler.h"
#include "chrome/browser/ui/autofill/save_address_bubble_controller.h"
#include "chrome/browser/ui/autofill/update_address_bubble_controller.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_active_state_manager/browser_active_state_manager.h"
#include "chrome/browser/ui/browser_window/public/browser_window_features.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/browser_tabstrip.h"
#include "chrome/browser/ui/browser_window_state.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_bubble_type.h"
#include "chrome/browser/ui/exclusive_access/exclusive_access_manager.h"
#include "chrome/browser/ui/exclusive_access/fullscreen_controller.h"
#include "chrome/browser/ui/find_bar/find_bar_controller.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_model.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "chrome/browser/ui/unload_controller.h"
#include "chrome/browser/ui/views/bubble_anchor_util_views.h"
#include "chrome/browser/ui/views/download/download_in_progress_dialog_view.h"
#include "chrome/browser/ui/window_metadata/window_metadata_controller.h"
#include "chrome/browser/ui/zoom/browser_window_zoom_observer.h"
#include "chrome/grit/generated_resources.h"
#include "components/find_in_page/find_notification_details.h"
#include "components/find_in_page/find_tab_helper.h"
#include "components/find_in_page/find_types.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/tabs/public/tab_interface.h"
#include "components/viz/common/frame_sinks/copy_output_result.h"
#include "components/web_modal/modal_dialog_host.h"
#include "components/zoom/zoom_controller.h"
#include "content/public/browser/keyboard_event_processing_result.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/web_contents.h"
#include "skia/ext/skia_utils_mac.h"
#include "third_party/skia/include/core/SkBitmap.h"
#include "ui/base/l10n/l10n_util.h"
#include "ui/base/mojom/window_show_state.mojom.h"
#include "ui/color/color_provider_manager.h"
#include "ui/gfx/geometry/rect.h"
#include "ui/gfx/mac/coordinate_conversion.h"
#include "ui/gfx/range/range.h"
#include "ui/native_theme/native_theme.h"
#include "url/gurl.h"

static_assert(!std::is_abstract_v<ClairBrowserWindow>);

ClairTakeOptions::ClairTakeOptions() = default;
ClairTakeOptions::ClairTakeOptions(ClairTakeOptions&&) = default;
ClairTakeOptions& ClairTakeOptions::operator=(ClairTakeOptions&&) = default;
ClairTakeOptions::~ClairTakeOptions() = default;

namespace {

// The browsers shown in native windows.
std::map<const BrowserWindowInterface*, ClairBrowserWindow*>& NativeWindows() {
  static base::NoDestructor<
      std::map<const BrowserWindowInterface*, ClairBrowserWindow*>>
      windows;
  return *windows;
}

// D9: a feature the native window doesn't host does nothing, and says so once.
void LogUnavailable(const char* feature) {
  static base::NoDestructor<std::set<std::string>> logged;
  if (logged->insert(feature).second) {
    LOG(WARNING) << "Clair: " << feature
                 << " isn't available in the native window";
  }
}

// D17: passwords and autofill are off, so their bubbles never show.
class ClairAutofillBubbleHandler : public autofill::AutofillBubbleHandler {
 public:
  autofill::AutofillBubbleBase* ShowSaveCreditCardBubble(
      content::WebContents*, autofill::SaveCardBubbleController*, bool) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowIbanBubble(content::WebContents*,
                                               autofill::IbanBubbleController*,
                                               bool,
                                               autofill::IbanBubbleType) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowOfferNotificationBubble(
      content::WebContents*,
      autofill::OfferNotificationBubbleController*,
      bool) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowSaveAutofillAiDataBubble(
      content::WebContents*,
      autofill::AutofillAiImportDataController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowAutofillAiLocalSaveNotification(
      content::WebContents*,
      autofill::AutofillAiImportDataController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowSaveAddressProfileBubble(
      content::WebContents*,
      std::unique_ptr<autofill::SaveAddressBubbleController>,
      bool) override {
    return Unavailable();
  }
#if BUILDFLAG(ENABLE_DICE_SUPPORT)
  autofill::AutofillBubbleBase* ShowAddressSignInPromo(
      content::WebContents*,
      const autofill::AutofillProfile&) override {
    return Unavailable();
  }
#endif
  autofill::AutofillBubbleBase* ShowUpdateAddressProfileBubble(
      content::WebContents*,
      std::unique_ptr<autofill::UpdateAddressBubbleController>,
      bool) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowFilledCardInformationBubble(
      content::WebContents*,
      autofill::FilledCardInformationBubbleController*,
      bool) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowVirtualCardEnrollBubble(
      content::WebContents*,
      autofill::VirtualCardEnrollBubbleController*,
      bool) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowVirtualCardEnrollConfirmationBubble(
      content::WebContents*,
      autofill::VirtualCardEnrollBubbleController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowMandatoryReauthBubble(
      content::WebContents*,
      autofill::MandatoryReauthBubbleController*,
      bool,
      autofill::MandatoryReauthBubbleType) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowSaveCardConfirmationBubble(
      content::WebContents*,
      autofill::SaveCardBubbleController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowSaveIbanConfirmationBubble(
      content::WebContents*,
      autofill::IbanBubbleController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowOmniboxAutofillBubble(
      content::WebContents*,
      autofill::OmniboxAutofillBubbleController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowPaymentsChurnedUsersBubble(
      content::WebContents*,
      autofill::PaymentsChurnedUsersBubbleController*,
      bool) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowPaymentsChurnedUsersConfirmationBubble(
      content::WebContents*,
      autofill::PaymentsChurnedUsersBubbleController*) override {
    return Unavailable();
  }
  autofill::AutofillBubbleBase* ShowWalletReminderNoticeBubble(
      content::WebContents*,
      autofill::WalletReminderNoticeBubbleController*,
      bool) override {
    return Unavailable();
  }

 private:
  static autofill::AutofillBubbleBase* Unavailable() {
    LogUnavailable("Autofill");
    return nullptr;
  }
};

// Whether the browser should handle a key the page didn't, as
// BrowserNativeWidgetMac decides.
bool ShouldHandleKeyboardEvent(const input::NativeWebKeyboardEvent& event) {
  if (event.skip_if_unhandled ||
      event.GetType() == input::NativeWebKeyboardEvent::Type::kChar) {
    return false;
  }
  return event.os_event && event.os_event.Get().type == NSEventTypeKeyDown;
}

NSRect ToNSRect(const gfx::Rect& rect) {
  return gfx::ScreenRectToNSRect(rect);
}

}  // namespace

// --- ClairLocationBar --------------------------------------------------------

ClairLocationBar::ClairLocationBar(ClairBrowserWindow* window)
    : LocationBar(nullptr), window_(window) {}

ClairLocationBar::~ClairLocationBar() = default;

void ClairLocationBar::FocusLocation(bool is_user_initiated,
                                     bool clear_focus_if_failed) {
  window_->SetFocusToLocationBar(is_user_initiated);
}

void ClairLocationBar::FocusSearch() {
  window_->SetFocusToLocationBar(true);
}

void ClairLocationBar::AnnounceAlert(const std::u16string& announcement) {}
void ClairLocationBar::UpdateFocusBehavior(bool toolbar_visible) {}

void ClairLocationBar::UpdateContentSettingsIcons() {
  // A permission was used or blocked: the URL field's indicators change.
  if (content::WebContents* active =
          window_->browser()->tab_strip_model()->GetActiveWebContents()) {
    [window_->bridge() tabChanged:active];
  }
}

void ClairLocationBar::SaveStateToContents(content::WebContents* contents) {}
void ClairLocationBar::Revert() {}
OmniboxView* ClairLocationBar::GetOmniboxView() {
  return nullptr;
}
OmniboxPopupView* ClairLocationBar::GetOmniboxPopupView() {
  return nullptr;
}
OmniboxController* ClairLocationBar::GetOmniboxController() {
  return nullptr;
}
bool ClairLocationBar::ShouldCloseOmniboxPopup(ui::MouseEvent* event) {
  return false;
}
content::WebContents* ClairLocationBar::GetWebContents() {
  return window_->browser()->tab_strip_model()->GetActiveWebContents();
}
LocationBarModel* ClairLocationBar::GetLocationBarModel() {
  return nullptr;
}
std::optional<bubble_anchor_util::AnchorConfiguration>
ClairLocationBar::GetChipAnchor() {
  return std::nullopt;
}
ChipController* ClairLocationBar::GetChipController() {
  return nullptr;
}
void ClairLocationBar::OnChanged() {}
void ClairLocationBar::UpdateWithoutTabRestore() {}
ui::TrackedElement* ClairLocationBar::GetAnchorOrNull() {
  return nullptr;
}
BrowserWindowInterface* ClairLocationBar::GetBrowser() {
  return window_->browser();
}
Profile* ClairLocationBar::GetProfile() {
  return window_->browser()->GetProfile();
}
bool ClairLocationBar::IsInitialized() const {
  return true;
}
bool ClairLocationBar::IsVisible() const {
  return false;
}
bool ClairLocationBar::IsDrawn() const {
  return false;
}
bool ClairLocationBar::IsFullscreen() const {
  return window_->IsFullscreen();
}
bool ClairLocationBar::IsEditingOrEmpty() const {
  return false;
}
bool ClairLocationBar::IsMouseHovered() const {
  return false;
}
bool ClairLocationBar::IsFocusWithin() const {
  return false;
}
void ClairLocationBar::InvalidateLayout() {}
gfx::Rect ClairLocationBar::Bounds() const {
  return gfx::Rect();
}
gfx::Rect ClairLocationBar::BoundsInScreen() const {
  return window_->SiteControlsAnchorInScreen();
}
gfx::Size ClairLocationBar::MinimumSize() const {
  return gfx::Size();
}
gfx::Size ClairLocationBar::PreferredSize() const {
  return gfx::Size();
}
void ClairLocationBar::Update(content::WebContents* contents) {
  if (contents) {
    [window_->bridge() tabChanged:contents];
  }
}
void ClairLocationBar::ResetTabState(content::WebContents* contents) {}
bool ClairLocationBar::HasSecurityStateChanged() {
  return false;
}
LocationBarTesting* ClairLocationBar::GetLocationBarForTesting() {
  return nullptr;
}

// --- ClairFindBar ------------------------------------------------------------

ClairFindBar::ClairFindBar(ClairBrowserWindow* window) : window_(window) {}

ClairFindBar::~ClairFindBar() {
  if (window_->find_bar() == this) {
    window_->ForgetFindBar();
  }
}

FindBarController* ClairFindBar::GetFindBarController() const {
  return controller_;
}

void ClairFindBar::SetFindBarController(FindBarController* find_bar_controller) {
  controller_ = find_bar_controller;
}

void ClairFindBar::Show(bool animate, bool focus) {
  visible_ = true;
  [window_->clair_window() showFindWithText:base::SysUTF16ToNSString(text_)];
}

void ClairFindBar::Hide(bool animate) {
  if (!visible_) {
    return;
  }
  visible_ = false;
  [window_->clair_window() hideFind];
}

void ClairFindBar::SetFocusAndSelection() {}

void ClairFindBar::ClearResults(
    const find_in_page::FindNotificationDetails& results) {
  [window_->clair_window() findResultDidChange:ClairFindResult{0, 0, true}];
}

void ClairFindBar::StopAnimation() {}
void ClairFindBar::MoveWindowIfNecessary() {}

void ClairFindBar::SetFindTextAndSelectedRange(const std::u16string& find_text,
                                               const gfx::Range& selected_range) {
  text_ = find_text;
  selected_range_ = selected_range;
}

std::u16string_view ClairFindBar::GetFindText() const {
  return text_;
}

gfx::Range ClairFindBar::GetSelectedRange() const {
  return selected_range_;
}

void ClairFindBar::UpdateUIForFindResult(
    const find_in_page::FindNotificationDetails& result,
    const std::u16string& find_text) {
  if (!find_text.empty()) {
    text_ = find_text;
  }
  [window_->clair_window()
      findResultDidChange:ClairFindResult{
                              std::max(result.active_match_ordinal(), 0),
                              std::max(result.number_of_matches(), 0),
                              result.final_update()}];
}

void ClairFindBar::AudibleAlert() {
  NSBeep();
}

bool ClairFindBar::IsFindBarVisible() const {
  return visible_;
}

void ClairFindBar::RestoreSavedFocus() {
  if (content::WebContents* active =
          window_->browser()->tab_strip_model()->GetActiveWebContents()) {
    active->Focus();
  }
}

bool ClairFindBar::HasGlobalFindPasteboard() const {
  return false;
}

void ClairFindBar::UpdateFindBarForChangedWebContents() {}

bool ClairFindBar::CanPopulateFromSelectedText() {
  return true;
}

const FindBarTesting* ClairFindBar::GetFindBarTesting() const {
  return nullptr;
}

bool ClairFindBar::HasFocus() const {
  return visible_;
}

void ClairFindBar::CloseOverlappingBubbles() {}

views::Widget* ClairFindBar::GetHostWidget() {
  return nullptr;
}

void ClairFindBar::FindFromField(const std::u16string& text, bool forward) {
  content::WebContents* active =
      window_->browser()->tab_strip_model()->GetActiveWebContents();
  auto* helper =
      active ? find_in_page::FindTabHelper::FromWebContents(active) : nullptr;
  if (!helper) {
    return;
  }
  if (controller_ && text != text_) {
    controller_->OnUserChangedFindText(text);
  }
  text_ = text;
  if (text.empty()) {
    helper->StopFinding(find_in_page::SelectionAction::kClear);
    ClearResults(helper->find_result());
    return;
  }
  helper->StartFinding(text, forward, /*case_sensitive=*/false,
                       /*find_match=*/true);
}

void ClairFindBar::EndFromField() {
  if (controller_) {
    controller_->EndFindSession(find_in_page::SelectionAction::kKeep,
                                find_in_page::ResultAction::kKeep);
  }
}

// --- ClairExclusiveAccessContext ---------------------------------------------

ClairExclusiveAccessContext::ClairExclusiveAccessContext(
    ClairBrowserWindow* window)
    : window_(window) {}

ClairExclusiveAccessContext::~ClairExclusiveAccessContext() {
  notice_timer_.Stop();
  if (notice_hide_callback_) {
    std::move(notice_hide_callback_)
        .Run(ExclusiveAccessBubbleHideReason::kInterrupted);
  }
}

Profile* ClairExclusiveAccessContext::GetProfile() {
  return window_->browser()->GetProfile();
}

bool ClairExclusiveAccessContext::IsFullscreen() const {
  return window_->IsFullscreen();
}

void ClairExclusiveAccessContext::EnterFullscreen(
    const url::Origin& origin,
    ExclusiveAccessBubbleType bubble_type,
    FullscreenTabParams fullscreen_tab_params) {
  // Only a page's own request shows the page alone. The browser's full screen
  // keeps the sidebar.
  if (!exclusive_access_bubble::IsExclusiveAccessModeBrowserFullscreen(
          bubble_type)) {
    SetPageFullscreen(true);
  }
  NSWindow* window = window_->ns_window();
  if (!(window.styleMask & NSWindowStyleMaskFullScreen)) {
    entered_window_fullscreen_ = true;
    entering_window_fullscreen_ = true;
    // The notice shows once the window is in full screen.
    [window toggleFullScreen:nil];
    return;
  }
  UpdateExclusiveAccessBubble({.origin = origin, .type = bubble_type}, {});
}

void ClairExclusiveAccessContext::ExitFullscreen() {
  SetPageFullscreen(false);
  HideNotice(ExclusiveAccessBubbleHideReason::kInterrupted);
  NSWindow* window = window_->ns_window();
  // Leave only what entering changed: a window already in full screen stays.
  if (entered_window_fullscreen_ &&
      (window.styleMask & NSWindowStyleMaskFullScreen)) {
    [window toggleFullScreen:nil];
  }
  entered_window_fullscreen_ = false;
}

bool ClairExclusiveAccessContext::DeferExitWhileEntering(NSEvent* event) {
  if (!entering_window_fullscreen_ || event.keyCode != 53 /* kVK_Escape */) {
    return false;
  }
  if (event.type == NSEventTypeKeyDown) {
    exit_when_entered_ = true;
  }
  return true;
}

void ClairExclusiveAccessContext::WindowFullscreenChanged(bool entered) {
  entering_window_fullscreen_ = false;
  if (entered && exit_when_entered_) {
    exit_when_entered_ = false;
    if (auto* manager = ExclusiveAccessManager::From(window_->browser())) {
      manager->ExitExclusiveAccess();
      return;
    }
  }
  exit_when_entered_ = false;
  // Chromium hears every transition, as from its own windows: leaving full
  // screen by the green button or the menu ends the page's full screen too.
  if (auto* manager = ExclusiveAccessManager::From(window_->browser())) {
    manager->fullscreen_controller()->WindowFullscreenStateChanged();
  }
  if (!entered) {
    entered_window_fullscreen_ = false;
    SetPageFullscreen(false);
    HideNotice(ExclusiveAccessBubbleHideReason::kInterrupted);
  }
}

void ClairExclusiveAccessContext::UpdateUIForTabFullscreen() {
  // A page entering or leaving full screen in a window already in full screen:
  // only what the card shows changes.
  auto* manager = ExclusiveAccessManager::From(window_->browser());
  content::WebContents* contents = GetWebContentsForExclusiveAccess();
  SetPageFullscreen(manager && contents &&
                    manager->fullscreen_controller()->exclusive_access_tab() ==
                        contents);
}

void ClairExclusiveAccessContext::UpdateExclusiveAccessBubble(
    const ExclusiveAccessBubbleParams& params,
    ExclusiveAccessBubbleHideCallback first_hide_callback) {
  const bool hide =
      (!params.has_download && params.type == EXCLUSIVE_ACCESS_BUBBLE_TYPE_NONE) ||
      exclusive_access_bubble::IsExclusiveAccessModeBrowserFullscreen(params.type);
  if (hide) {
    if (first_hide_callback) {
      std::move(first_hide_callback)
          .Run(ExclusiveAccessBubbleHideReason::kNotShown);
    }
    HideNotice(ExclusiveAccessBubbleHideReason::kInterrupted);
    return;
  }
  HideNotice(ExclusiveAccessBubbleHideReason::kInterrupted);
  const std::u16string text = exclusive_access_bubble::GetInstructionTextForType(
      params.type, u"Esc", std::nullopt, params.has_download,
      /*notify_overridden=*/false);
  [window_->clair_window()
      showExclusiveAccessNotice:base::SysUTF16ToNSString(text)];
  notice_visible_ = true;
  notice_hide_callback_ = std::move(first_hide_callback);
  notice_timer_.Start(
      FROM_HERE, ExclusiveAccessBubble::kShowTime,
      base::BindOnce(&ClairExclusiveAccessContext::HideNotice,
                     base::Unretained(this),
                     ExclusiveAccessBubbleHideReason::kTimeout));
}

bool ClairExclusiveAccessContext::IsExclusiveAccessBubbleDisplayed() const {
  return notice_visible_;
}

void ClairExclusiveAccessContext::OnExclusiveAccessUserInput() {}

content::WebContents*
ClairExclusiveAccessContext::GetWebContentsForExclusiveAccess() {
  return window_->browser()->tab_strip_model()->GetActiveWebContents();
}

bool ClairExclusiveAccessContext::CanUserEnterFullscreen() const {
  return true;
}

bool ClairExclusiveAccessContext::CanUserExitFullscreen() const {
  return true;
}

void ClairExclusiveAccessContext::SetPageFullscreen(bool fullscreen) {
  if (page_fullscreen_ == fullscreen) {
    return;
  }
  page_fullscreen_ = fullscreen;
  [window_->clair_window() pageFullscreenDidChange:fullscreen];
}

void ClairExclusiveAccessContext::HideNotice(
    ExclusiveAccessBubbleHideReason reason) {
  notice_timer_.Stop();
  if (notice_visible_) {
    notice_visible_ = false;
    [window_->clair_window() showExclusiveAccessNotice:nil];
  }
  if (notice_hide_callback_) {
    std::move(notice_hide_callback_).Run(reason);
  }
}

// --- ClairModalDialogHost ----------------------------------------------------

ClairModalDialogHost::ClairModalDialogHost(ClairBrowserWindow* window)
    : window_(window) {}

ClairModalDialogHost::~ClairModalDialogHost() {
  for (auto& observer : observers_) {
    observer.OnHostDestroying();
  }
}

// The host view is the window's content view, which Chromium also uses as
// the parent of browser-modal dialogs (`platform_util::GetViewForWindow`), so
// both kinds of dialog share one host. They're placed over the card.
gfx::NativeView ClairModalDialogHost::GetHostView() const {
  return gfx::NativeView(window_->ns_window().contentView);
}

// The card's frame in the content view, top-left origin.
gfx::Rect ClairModalDialogHost::CardRect() const {
  NSView* content = window_->ns_window().contentView;
  if (!content) {
    return gfx::Rect();
  }
  id<ClairWindow> window = window_->clair_window();
  NSView* card = window ? window.pageContainerView : nil;
  NSRect rect = card && card.window == content.window
                    ? [content convertRect:card.bounds fromView:card]
                    : content.bounds;
  if (!content.flipped) {
    rect.origin.y = NSHeight(content.bounds) - NSMaxY(rect);
  }
  return gfx::Rect(NSMinX(rect), NSMinY(rect), NSWidth(rect), NSHeight(rect));
}

gfx::Point ClairModalDialogHost::GetDialogPosition(const gfx::Size& size) {
  const gfx::Rect card = CardRect();
  return gfx::Point(card.x() + std::max(0, (card.width() - size.width()) / 2),
                    card.y());
}

gfx::Size ClairModalDialogHost::GetMaximumDialogSize() {
  return CardRect().size();
}

void ClairModalDialogHost::AddObserver(
    web_modal::ModalDialogHostObserver* observer) {
  observers_.AddObserver(observer);
}

void ClairModalDialogHost::RemoveObserver(
    web_modal::ModalDialogHostObserver* observer) {
  observers_.RemoveObserver(observer);
}

void ClairModalDialogHost::NotifyPositionRequiresUpdate() {
  for (auto& observer : observers_) {
    observer.OnPositionRequiresUpdate();
  }
}

// --- ClairStatusBubble -------------------------------------------------------

ClairStatusBubble::ClairStatusBubble(ClairBrowserWindow* window)
    : window_(window) {}

ClairStatusBubble::~ClairStatusBubble() = default;

void ClairStatusBubble::SetStatus(const std::u16string& status) {
  status_ = status;
  Update();
}

void ClairStatusBubble::SetURL(const GURL& url) {
  url_ = url.is_empty() ? std::u16string() : base::UTF8ToUTF16(url.spec());
  Update();
}

void ClairStatusBubble::Hide() {
  status_.clear();
  url_.clear();
  Update();
}

void ClairStatusBubble::MouseMoved(bool left_content) {}

void ClairStatusBubble::Update() {
  const std::u16string& text = status_.empty() ? url_ : status_;
  [window_->clair_window()
      statusTextDidChange:text.empty() ? nil : base::SysUTF16ToNSString(text)];
}

// --- ClairBrowserWindow ------------------------------------------------------

ClairBrowserWindow::ClairBrowserWindow(Browser* browser)
    : browser_(browser),
      location_bar_(this),
      modal_dialog_host_(this),
      exclusive_access_context_(this),
      status_bubble_(this),
      autofill_bubble_handler_(std::make_unique<ClairAutofillBubbleHandler>()) {
  NativeWindows()[browser] = this;

  gfx::Rect bounds;
  ui::mojom::WindowShowState show_state = ui::mojom::WindowShowState::kDefault;
  chrome::GetSavedWindowBoundsAndShowState(browser, &bounds, &show_state);
  initial_show_state_ = show_state;
  restored_bounds_ = bounds;
  ns_window_ = [[ClairNativeWindow alloc] initWithBrowserWindow:this
                                                    contentRect:ToNSRect(bounds)];
  [ns_window_ setFrame:ToNSRect(bounds) display:NO];

  // add-spaces D3: a new window shows the Space last shown in a key window,
  // which is the Space of the window it was opened from; an incognito or
  // guest window, its profile's own.
  space_tabs_ = ClairSpaceTabs::ForProfile(browser->GetProfile());
  shown_space_ = space_tabs_->is_regular()
                     ? clair::ClairSpaceStore::Get()->last_space()
                     : space_tabs_->private_space();

  bridge_ = [[ClairChromiumBrowser alloc] initWithBrowserWindow:this];
  // Before the Peeks, so the lists hear of a tab before it's linked.
  space_tabs_->AddBrowser(this);
  extensions_ = std::make_unique<ClairExtensions>(this);
  downloads_ = std::make_unique<ClairDownloads>(this);
  // After the bridge, so the bridge hears of tab strip changes first.
  peeks_ = std::make_unique<ClairPeeks>(this);
  clair::ApplyPasswordAndAutofillOverrides(browser->GetProfile());

  // D2: ClairUI returns a window for every browser. A nil window is a bug that
  // must not go unnoticed, so Clair stops rather than show Chromium's window.
  clair_window_ = clair::CreateClairWindow(bridge_);
  CHECK(clair_window_) << "ClairUI returned no window for a browser";
  [bridge_ attachWindow:clair_window_];

  if (auto* zoom = BrowserWindowZoomObserver::From(browser)) {
    zoom_subscription_ = zoom->RegisterZoomChangedCallback(base::BindRepeating(
        &ClairBrowserWindow::ZoomChanged, weak_factory_.GetWeakPtr()));
  }
}

ClairBrowserWindow::~ClairBrowserWindow() {
  browser_->GetFeatures().TearDownPreBrowserWindowDestruction();
  peeks_.reset();
  if (space_tabs_) {
    space_tabs_->RemoveBrowser(this);
    space_tabs_ = nullptr;
  }
  DetachFromClairUI();
  zoom_subscription_ = {};
  extensions_.reset();
  downloads_.reset();
  [ns_window_ detachBrowserWindow];
  [ns_window_ orderOut:nil];
  [ns_window_ close];
  NativeWindows().erase(browser_);
}

// static
ClairBrowserWindow* ClairBrowserWindow::FromBrowser(
    const BrowserWindowInterface* browser) {
  auto found = NativeWindows().find(browser);
  return found == NativeWindows().end() ? nullptr : found->second;
}

// static
ClairBrowserWindow* ClairBrowserWindow::FromWebContents(
    content::WebContents* contents) {
  tabs::TabInterface* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  return tab ? FromBrowser(tab->GetBrowserWindowInterface()) : nullptr;
}

// static
std::vector<ClairBrowserWindow*> ClairBrowserWindow::All() {
  std::vector<ClairBrowserWindow*> windows;
  for (const auto& [browser, window] : NativeWindows()) {
    windows.push_back(window);
  }
  return windows;
}

void ClairBrowserWindow::DetachFromClairUI() {
  if (detached_) {
    return;
  }
  detached_ = true;
  [clair_window_ browserDidClose];
  [bridge_ detach];
  clair_window_ = nil;
}

std::set<content::WebContents*> ClairBrowserWindow::PagesShownWith(
    content::WebContents* active) const {
  if (peeks_) {
    return peeks_->PagesShownWith(active);
  }
  return active ? std::set<content::WebContents*>{active}
                : std::set<content::WebContents*>();
}

// --- Spaces (add-spaces D3, D4, D5) ---

void ClairBrowserWindow::SetShownSpace(const std::string& space) {
  if (space == shown_space_) {
    return;
  }
  const std::string previous = shown_space_;
  shown_space_ = space;
  if (IsActive() && space_tabs_ && space_tabs_->is_regular()) {
    clair::ClairSpaceStore::Get()->SetLastSpace(space);
  }
  [bridge_ shownSpaceChangedFrom:previous];
}

namespace {

// share-tabs-across-windows D2: the key window takes back the tab of its
// still, unless the still has ended meanwhile.
void PostTakeBack(base::WeakPtr<ClairBrowserWindow> window) {
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<ClairBrowserWindow> window) {
                       if (!window || !window->IsActive()) {
                         return;
                       }
                       if (tabs::TabInterface* still =
                               window->still_tab().Get()) {
                         window->ActivateRow(still);
                       }
                     },
                     window));
}

}  // namespace

// static
ClairBrowserWindow* ClairBrowserWindow::HolderOf(const tabs::TabInterface* tab) {
  return tab ? FromBrowser(tab->GetBrowserWindowInterface()) : nullptr;
}

namespace {

// The row `tab` shows in: its parent if it's a Peek, in whichever window.
tabs::TabInterface* RowOf(tabs::TabInterface* tab) {
  ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(tab);
  ClairPeeks* peeks = holder ? holder->peeks() : nullptr;
  tabs::TabInterface* parent = peeks && tab ? peeks->ParentOf(tab) : nullptr;
  return parent ? parent : tab;
}

// share-tabs-across-windows D2: `row` stopped showing in its window. If no
// window shows it now, the most recently active window with a still of it
// takes it back, without becoming key, as Arc does.
void GiveBackToStill(tabs::TabHandle handle) {
  tabs::TabInterface* row = handle.Get();
  ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(row);
  if (!row || !holder || holder->IsActiveRow(row)) {
    return;
  }
  ClairBrowserWindow* target = nullptr;
  ForEachCurrentBrowserWindowInterfaceOrderedByActivation(
      [&target, handle](BrowserWindowInterface* candidate) {
        ClairBrowserWindow* window = ClairBrowserWindow::FromBrowser(candidate);
        if (window && window->still_tab() == handle) {
          target = window;
          return false;
        }
        return true;
      });
  // Only into the Space the window shows, which the still belongs to.
  if (!target || target == holder || !target->space_tabs() ||
      target->space_tabs()->SpaceOf(row) != target->shown_space()) {
    return;
  }
  target->ActivateRow(row);
}

// When the user last looked at `row`, or at its Peek.
base::Time LastActive(tabs::TabInterface* row) {
  base::Time time = row->GetLastActiveTime();
  ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(row);
  ClairPeeks* peeks = holder ? holder->peeks() : nullptr;
  if (tabs::TabInterface* peek = peeks ? peeks->PeekOf(row) : nullptr) {
    time = std::max(time, peek->GetLastActiveTime());
  }
  return time;
}

}  // namespace

std::vector<tabs::TabInterface*> ClairBrowserWindow::SpaceTabs() const {
  if (!space_tabs_) {
    return std::vector<tabs::TabInterface*>();
  }
  // share-tabs-across-windows D1: every window lists the Space's tabs; an
  // incognito or guest window lists its own.
  return space_tabs_->is_regular() ? space_tabs_->TabsIn(shown_space_)
                                   : space_tabs_->TabsIn(shown_space_, browser_);
}

std::vector<tabs::TabInterface*> ClairBrowserWindow::Rows() const {
  std::vector<tabs::TabInterface*> rows = SpaceTabs();
  std::erase_if(rows,
                [](tabs::TabInterface* tab) { return RowOf(tab) != tab; });
  return rows;
}

bool ClairBrowserWindow::IsActiveRow(const tabs::TabInterface* tab) const {
  tabs::TabInterface* active = browser_->tab_strip_model()->GetActiveTab();
  if (!tab || !active) {
    return false;
  }
  return active == tab || (peeks_ && peeks_->ParentOf(active) == tab);
}

tabs::TabInterface* ClairBrowserWindow::HighlightedRow() const {
  if (tabs::TabInterface* still = still_tab_.Get()) {
    return still;
  }
  tabs::TabInterface* active = browser_->tab_strip_model()->GetActiveTab();
  if (!active || ClairSpaceTabs::IsPlaceholder(active->GetContents())) {
    return nullptr;
  }
  tabs::TabInterface* parent = peeks_ ? peeks_->ParentOf(active) : nullptr;
  return parent ? parent : active;
}

bool ClairBrowserWindow::IsShownElsewhere(const tabs::TabInterface* row) const {
  ClairBrowserWindow* holder = HolderOf(row);
  return holder && holder != this && holder->IsActiveRow(row);
}

void ClairBrowserWindow::ActivateTab(tabs::TabInterface* tab,
                                     ClairTakeOptions options) {
  ClairBrowserWindow* holder = HolderOf(tab);
  if (tab && holder && holder != this) {
    Take(tab, std::move(options));
    return;
  }
  TabStripModel* strip = browser_->tab_strip_model();
  const int index = tab ? strip->GetIndexOfTab(tab) : TabStripModel::kNoTab;
  if (index != TabStripModel::kNoTab) {
    base::AutoReset<bool> choosing(&choosing_next_,
                                   choosing_next_ || options.choosing);
    strip->ActivateTabAt(index,
                         TabStripUserGestureDetails(
                             TabStripUserGestureDetails::GestureType::kOther));
  }
  if (options.choosing) {
    came_from_ = tabs::TabHandle::Null();
  }
  if (options.then) {
    std::move(options.then).Run();
  }
}

void ClairBrowserWindow::ActivateRow(tabs::TabInterface* row,
                                     ClairTakeOptions options) {
  if (!row) {
    if (options.then) {
      std::move(options.then).Run();
    }
    return;
  }
  ClairBrowserWindow* holder = HolderOf(row);
  ClairPeeks* peeks = holder ? holder->peeks() : nullptr;
  tabs::TabInterface* peek = peeks ? peeks->PeekOf(row) : nullptr;
  ActivateTab(peek ? peek : row, std::move(options));
}

void ClairBrowserWindow::ChooseRow(tabs::TabInterface* row,
                                   base::OnceClosure* then) {
  ClairTakeOptions options;
  options.choosing = true;
  if (then) {
    // A close waits for the tab it shows instead: the window keeps its tab
    // until the next one is here.
    options.then = std::move(*then);
  } else {
    // Chromium acts at once, as on a page's answer to its leave-page
    // confirmation: the tab moves now, and the still's image follows.
    options.wait_for_copy = false;
  }
  ActivateRow(row, std::move(options));
}

bool ClairBrowserWindow::ShowNextRow(tabs::TabInterface* row,
                                     base::OnceClosure* then) {
  const std::vector<tabs::TabInterface*> rows = Rows();
  auto it = std::ranges::find(rows, row);
  if (it == rows.end()) {
    return false;
  }
  // share-tabs-across-windows D3: from every row, a row another window shows
  // included; it's taken from there.
  tabs::TabInterface* next = nullptr;
  tabs::TabInterface* came_from = came_from_.Get();
  if (came_from && came_from != row &&
      std::ranges::find(rows, came_from) != rows.end()) {
    next = came_from;
  } else if (it != rows.begin()) {
    next = *(it - 1);
  } else if (it + 1 != rows.end()) {
    next = *(it + 1);
  }
  if (!next) {
    return false;
  }
  ChooseRow(next, then);
  return true;
}

bool ClairBrowserWindow::ShowTabOfAnotherSpace(tabs::TabInterface* row,
                                               base::OnceClosure* then) {
  if (!row || !space_tabs_ || !space_tabs_->is_regular()) {
    return false;
  }
  const std::string space = space_tabs_->SpaceOf(row);
  tabs::TabInterface* best = nullptr;
  for (const std::string& other : space_tabs_->SpacesWithTabs()) {
    if (other == space) {
      continue;
    }
    for (tabs::TabInterface* tab : space_tabs_->TabsIn(other)) {
      if (RowOf(tab) != tab || IsShownElsewhere(tab)) {
        continue;
      }
      if (!best || LastActive(tab) > LastActive(best)) {
        best = tab;
      }
    }
  }
  if (!best) {
    return false;
  }
  // The window's shown Space follows the tab (add-spaces D3).
  ChooseRow(best, then);
  return true;
}

void ClairBrowserWindow::CloseTab(tabs::TabInterface* tab) {
  if (!tab) {
    return;
  }
  // share-tabs-across-windows D3: in whichever window holds it, which picks
  // its own next tab.
  if (ClairBrowserWindow* holder = HolderOf(tab); holder && holder != this) {
    holder->CloseTab(tab);
    return;
  }
  // D4: Clair picks the next tab first; without one in the Space, the most
  // recently active tab of another Space, or else Chromium's choice stands.
  if (IsActiveRow(tab)) {
    if (tab->GetContents()->NeedToFireBeforeUnloadOrUnloadEvents()) {
      // Chromium asks the page before it closes the tab, and its leave-page
      // confirmation makes the tab active again. The choice waits for the
      // page's answer, in BeforeUnloadFired().
      pending_close_ = tab->GetHandle();
    } else {
      // The tab closes once the next one shows, which may wait for a page's
      // copy in another window (share-tabs-across-windows D2): closing first
      // would close a window holding no other tab.
      base::OnceClosure close =
          base::BindOnce(&ClairBrowserWindow::CloseTabNow,
                         weak_factory_.GetWeakPtr(), tab->GetHandle());
      if (!ShowNextRow(tab, &close) && RowOf(tab) == tab) {
        ShowTabOfAnotherSpace(tab, &close);
      }
      if (close) {
        std::move(close).Run();
      }
      return;
    }
  }
  CloseTabNow(tab->GetHandle());
}

void ClairBrowserWindow::CloseTabNow(tabs::TabHandle handle) {
  tabs::TabInterface* tab = handle.Get();
  TabStripModel* strip = browser_->tab_strip_model();
  const int index = tab ? strip->GetIndexOfTab(tab) : TabStripModel::kNoTab;
  if (index != TabStripModel::kNoTab) {
    strip->CloseWebContentsAt(index,
                              TabCloseTypes::CLOSE_USER_GESTURE |
                                  TabCloseTypes::CLOSE_CREATE_HISTORICAL_TAB);
  }
}

void ClairBrowserWindow::BeforeUnloadFired(content::WebContents* contents,
                                           bool proceed) {
  tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  if (!tab || tab->GetHandle() != pending_close_) {
    return;
  }
  pending_close_ = tabs::TabHandle::Null();
  // Staying on the page leaves everything as it was, the came-from row too.
  if (proceed && IsActiveRow(tab) && !ShowNextRow(tab) && RowOf(tab) == tab) {
    ShowTabOfAnotherSpace(tab);
  }
}

void ClairBrowserWindow::CloseTabsBelow(tabs::TabInterface* tab) {
  if (!tab || !space_tabs_) {
    return;
  }
  // Below the tab's Peek, which goes only with the tab (add-peek D8), over
  // the Space's rows in every window (share-tabs-across-windows D3).
  ClairBrowserWindow* holder = HolderOf(tab);
  ClairPeeks* peeks = holder ? holder->peeks() : nullptr;
  tabs::TabInterface* last = peeks ? peeks->LastOfFamily(tab) : tab;
  const std::string space = space_tabs_->SpaceOf(tab);
  const std::vector<tabs::TabInterface*> tabs =
      space_tabs_->is_regular() ? space_tabs_->TabsIn(space)
                                : space_tabs_->TabsIn(space, browser_);
  auto it = std::ranges::find(tabs, last);
  if (it == tabs.end()) {
    return;
  }
  std::vector<tabs::TabHandle> below;
  for (++it; it != tabs.end(); ++it) {
    below.push_back((*it)->GetHandle());
  }
  for (const tabs::TabHandle& handle : below) {
    CloseTab(handle.Get());
  }
}

void ClairBrowserWindow::OpenNewTabPage(bool show_command_bar) {
  {
    base::AutoReset<bool> choosing(&choosing_next_, true);
    // An empty URL is the new tab page; clair::NewTabIndex puts it at the
    // top, and it joins the shown Space.
    chrome::AddTabAt(browser_, GURL(), -1, /*foreground=*/true);
  }
  came_from_ = tabs::TabHandle::Null();
  if (show_command_bar) {
    [clair_window_ showCommandBarWithMode:ClairCommandBarModeCurrentTab];
  }
}

void ClairBrowserWindow::ShowSpace(const std::string& space) {
  if (!space_tabs_ || !space_tabs_->is_regular() ||
      !clair::ClairSpaceStore::Get()->Contains(space) ||
      space == shown_space_) {
    return;
  }
  // share-tabs-across-windows D3: the tab last active in the Space here,
  // unless another window shows it; else the Space's most recently active row
  // that no window shows, from any window.
  std::vector<tabs::TabInterface*> rows = space_tabs_->TabsIn(space);
  std::erase_if(rows,
                [](tabs::TabInterface* tab) { return RowOf(tab) != tab; });
  tabs::TabInterface* target = nullptr;
  if (auto last = last_active_.find(space); last != last_active_.end()) {
    tabs::TabInterface* tab = last->second.Get();
    tabs::TabInterface* row = tab ? RowOf(tab) : nullptr;
    if (row && std::ranges::find(rows, row) != rows.end() &&
        !IsShownElsewhere(row)) {
      target = tab;
    }
  }
  if (!target) {
    for (tabs::TabInterface* row : rows) {
      if (!IsShownElsewhere(row) &&
          (!target || LastActive(row) > LastActive(target))) {
        target = row;
      }
    }
  }
  // ClairUI hears of the Space before the tab that shows it.
  SetShownSpace(space);
  if (!target) {
    OpenNewTabPage(/*show_command_bar=*/true);
    return;
  }
  if (RowOf(target) == target) {
    ActivateRow(target);
  } else {
    ActivateTab(target);
  }
}

bool ClairBrowserWindow::ExecuteTabCommand(int command) {
  const bool select_index =
      command >= IDC_SELECT_TAB_0 && command <= IDC_SELECT_TAB_7;
  const bool step = command == IDC_SELECT_NEXT_TAB ||
                    command == IDC_SELECT_PREVIOUS_TAB ||
                    command == IDC_CYCLE_TO_NEXT_TAB ||
                    command == IDC_CYCLE_TO_PREV_TAB;
  TabStripModel* strip = browser_->tab_strip_model();
  tabs::TabInterface* active = strip->GetActiveTab();
  // While the window shows a still, the still's row stands for the active
  // one, as the sidebar highlights it.
  tabs::TabInterface* active_row = HighlightedRow();
  if (select_index || step || command == IDC_SELECT_LAST_TAB) {
    // Over the rows the sidebar lists, where a tab and its Peek are one
    // stop, and never into another Space. A row another window holds is
    // taken from it (share-tabs-across-windows D3).
    const std::vector<tabs::TabInterface*> rows = Rows();
    if (rows.empty()) {
      return true;
    }
    const int count = static_cast<int>(rows.size());
    if (select_index) {
      const int index = command - IDC_SELECT_TAB_0;
      if (index < count) {
        ActivateRow(rows[index]);
      }
      return true;
    }
    if (command == IDC_SELECT_LAST_TAB) {
      ActivateRow(rows.back());
      return true;
    }
    auto it = std::ranges::find(rows, active_row);
    const int position =
        it == rows.end() ? 0 : static_cast<int>(it - rows.begin());
    const bool forward = command == IDC_SELECT_NEXT_TAB ||
                         command == IDC_CYCLE_TO_NEXT_TAB;
    ActivateRow(rows[(position + (forward ? 1 : -1) + count) % count]);
    return true;
  }
  switch (command) {
    case IDC_MOVE_TAB_NEXT:
    case IDC_MOVE_TAB_PREVIOUS: {
      // One row down or up, stopping at the ends as Chromium does. The strip
      // keeps its order, which means nothing to the user (D2).
      const std::vector<tabs::TabInterface*> rows = Rows();
      auto it = std::ranges::find(rows, active_row);
      if (!space_tabs_ || it == rows.end()) {
        return true;
      }
      const bool down = command == IDC_MOVE_TAB_NEXT;
      if (down ? it + 1 != rows.end() : it != rows.begin()) {
        space_tabs_->MoveTabBeside(active_row, down ? *(it + 1) : *(it - 1),
                                   /*after=*/down);
      }
      return true;
    }
    case IDC_CLOSE_TAB:
      // A Peek's Cmd+W is ClairPeeks'; it runs first. While the window shows
      // a still, the still's row is the one closed.
      CloseTab(still_tab_.Get() ? still_tab_.Get() : active);
      return true;
    case IDC_WINDOW_CLOSE_TABS_TO_RIGHT:
      CloseTabsBelow(active_row);
      return true;
    case IDC_WINDOW_CLOSE_OTHER_TABS: {
      std::vector<tabs::TabHandle> others;
      for (tabs::TabInterface* row : Rows()) {
        if (row != active_row) {
          others.push_back(row->GetHandle());
        }
      }
      for (const tabs::TabHandle& handle : others) {
        CloseTab(handle.Get());
      }
      return true;
    }
    default:
      return false;
  }
}

// --- Tabs shared across windows (share-tabs-across-windows D1, D2, D4) ---

bool ClairBrowserWindow::CanTake(const tabs::TabInterface* tab) const {
  ClairBrowserWindow* holder = HolderOf(tab);
  return tab && holder && holder != this && space_tabs_ &&
         space_tabs_->is_regular() && holder->space_tabs() == space_tabs_ &&
         !detached_ && !browser_->IsDeleteScheduled() &&
         !ClairSpaceTabs::IsPlaceholder(tab->GetContents());
}

void ClairBrowserWindow::Take(tabs::TabInterface* tab,
                              ClairTakeOptions options) {
  if (!CanTake(tab)) {
    if (options.then) {
      std::move(options.then).Run();
    }
    return;
  }
  tabs::TabInterface* row = RowOf(tab);
  const tabs::TabHandle handle = tab->GetHandle();
  ClairBrowserWindow* holder = HolderOf(tab);
  // D2: the holder keeps a still of what it shows.
  if (holder->IsActiveRow(row)) {
    if (options.wait_for_copy) {
      // The tab waits for its page's copy, taken while the holder still
      // draws it.
      if (taking_ == handle) {
        if (options.then) {
          std::move(options.then).Run();
        }
        return;
      }
      taking_ = handle;
      CopyPage(row, base::BindOnce(&ClairBrowserWindow::FinishTake,
                                   weak_factory_.GetWeakPtr(), handle,
                                   std::move(options)));
      return;
    }
    // At once: the still's image follows if the copy comes.
    holder->CopyPage(row,
                     base::BindOnce(&ClairBrowserWindow::SetStillImage,
                                    holder->weak_factory_.GetWeakPtr(),
                                    row->GetHandle()));
  }
  FinishTake(handle, std::move(options), SkBitmap());
}

void ClairBrowserWindow::FinishTake(tabs::TabHandle handle,
                                    ClairTakeOptions options,
                                    const SkBitmap& copy) {
  if (taking_ == handle) {
    taking_ = tabs::TabHandle::Null();
  }
  tabs::TabInterface* tab = handle.Get();
  if (!CanTake(tab)) {
    // Here already, as by another way meanwhile, it only becomes active.
    if (tab && HolderOf(tab) == this) {
      ActivateTab(tab, std::move(options));
    } else if (options.then) {
      std::move(options.then).Run();
    }
    return;
  }
  tabs::TabInterface* row = RowOf(tab);
  ClairBrowserWindow* holder = HolderOf(tab);
  if (holder->IsActiveRow(row)) {
    holder->BeginStill(row, copy);
  }
  MoveFamilyHere(holder, row);
  ActivateTab(handle.Get(), std::move(options));
}

void ClairBrowserWindow::SetStillImage(tabs::TabHandle handle,
                                       const SkBitmap& copy) {
  if (still_tab_ != handle || still_image_ || copy.drawsNothing()) {
    return;
  }
  still_image_ = StillImageFrom(copy);
  [bridge_ stillChanged];
}

NSImage* ClairBrowserWindow::StillImageFrom(const SkBitmap& copy) const {
  if (copy.drawsNothing()) {
    return nil;
  }
  // In points, as the card lays it out.
  const CGFloat scale =
      ns_window_.backingScaleFactor > 0 ? ns_window_.backingScaleFactor : 1;
  NSImage* image = skia::SkBitmapToNSImage(copy);
  image.size = NSMakeSize(copy.width() / scale, copy.height() / scale);
  return image;
}

void ClairBrowserWindow::CopyPage(
    tabs::TabInterface* row,
    base::OnceCallback<void(const SkBitmap&)> done) {
  using Pending = base::RefCountedData<base::OnceCallback<void(const SkBitmap&)>>;
  auto pending = base::MakeRefCounted<Pending>(std::move(done));
  // The tab's own page, never its Peek's, which shows over it.
  content::RenderWidgetHostView* view =
      row ? row->GetContents()->GetRenderWidgetHostView() : nullptr;
  if (!view) {
    std::move(pending->data).Run(SkBitmap());
    return;
  }
  // On the UI thread, as Chromium's tab thumbnails take theirs.
  view->CopyFromSurface(
      gfx::Rect(), gfx::Size(), base::Milliseconds(250),
      base::BindOnce(
          [](scoped_refptr<Pending> pending,
             const content::CopyFromSurfaceResult& result) {
            if (pending->data.is_null()) {
              return;
            }
            std::move(pending->data)
                .Run(result.has_value() ? result->bitmap : SkBitmap());
          },
          pending));
  // Should the copy never answer, the take goes ahead without a still image.
  base::SequencedTaskRunner::GetCurrentDefault()->PostDelayedTask(
      FROM_HERE,
      base::BindOnce(
          [](scoped_refptr<Pending> pending) {
            if (!pending->data.is_null()) {
              std::move(pending->data).Run(SkBitmap());
            }
          },
          pending),
      base::Milliseconds(400));
}

void ClairBrowserWindow::MoveFamilyHere(ClairBrowserWindow* from,
                                        tabs::TabInterface* row) {
  if (!from || from == this || !row || !space_tabs_) {
    return;
  }
  TabStripModel* source = from->browser()->tab_strip_model();
  TabStripModel* target = browser_->tab_strip_model();
  // The pair leaves the Peek table there before the strip hears of it.
  tabs::TabInterface* peek = from->peeks() ? from->peeks()->Release(row) : nullptr;
  std::vector<tabs::TabInterface*> family{row};
  if (peek) {
    family.push_back(peek);
  }
  for (tabs::TabInterface* member : family) {
    space_tabs_->BeginMove(member);
  }
  // The tabs and their handles survive the move (design Context).
  std::vector<std::unique_ptr<tabs::TabModel>> models;
  for (tabs::TabInterface* member : family) {
    const int index = source->GetIndexOfTab(member);
    if (index != TabStripModel::kNoTab) {
      models.push_back(source->DetachTabAtForInsertion(index));
    }
  }
  for (std::unique_ptr<tabs::TabModel>& model : models) {
    target->InsertDetachedTabAt(target->count(), std::move(model),
                                AddTabTypes::ADD_NONE);
  }
  for (tabs::TabInterface* member : family) {
    space_tabs_->EndMove(member);
  }
  if (peek && peeks_ && target->GetIndexOfTab(row) != TabStripModel::kNoTab &&
      target->GetIndexOfTab(peek) != TabStripModel::kNoTab) {
    peeks_->Adopt(row, peek);
  }
}

tabs::TabInterface* ClairBrowserWindow::placeholder() const {
  tabs::TabInterface* tab = placeholder_.Get();
  return tab && ClairSpaceTabs::IsPlaceholder(tab->GetContents()) &&
                 browser_->tab_strip_model()->GetIndexOfTab(tab) !=
                     TabStripModel::kNoTab
             ? tab
             : nullptr;
}

void ClairBrowserWindow::BeginStill(tabs::TabInterface* row,
                                    const SkBitmap& copy) {
  if (!row || detached_ || browser_->IsDeleteScheduled()) {
    return;
  }
  still_tab_ = row->GetHandle();
  still_image_ = StillImageFrom(copy);
  // The placeholder: Chromium needs an active tab, and any real tab would run
  // as visible behind the still. It's in no Space, so the window keeps the
  // one it shows.
  {
    base::AutoReset<bool> inserting(&inserting_placeholder_, true);
    content::WebContents* contents = chrome::AddAndReturnTabAt(
        browser_, GURL(), browser_->tab_strip_model()->count(),
        /*foreground=*/true);
    if (contents) {
      ClairSpaceTabs::MarkPlaceholder(contents);
      if (tabs::TabInterface* tab =
              tabs::TabInterface::MaybeGetFromContents(contents)) {
        placeholder_ = tab->GetHandle();
      }
    }
  }
  [bridge_ stillChanged];
}

void ClairBrowserWindow::EndStill() {
  const bool had_still = still_tab_ != tabs::TabHandle::Null();
  still_tab_ = tabs::TabHandle::Null();
  still_image_ = nil;
  tabs::TabInterface* placeholder = this->placeholder();
  placeholder_ = tabs::TabHandle::Null();
  if (had_still) {
    [bridge_ stillChanged];
  }
  if (!placeholder) {
    return;
  }
  // Not from inside the strip's notification, which can't be re-entered.
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(
          [](base::WeakPtr<ClairBrowserWindow> window, tabs::TabHandle handle) {
            tabs::TabInterface* tab = handle.Get();
            if (!window || !tab ||
                !ClairSpaceTabs::IsPlaceholder(tab->GetContents())) {
              return;
            }
            TabStripModel* strip = window->browser()->tab_strip_model();
            const int index = strip->GetIndexOfTab(tab);
            if (index != TabStripModel::kNoTab && strip->GetActiveTab() != tab) {
              strip->CloseWebContentsAt(index, TabCloseTypes::CLOSE_NONE);
            }
          },
          weak_factory_.GetWeakPtr(), placeholder->GetHandle()));
}

void ClairBrowserWindow::StillTabClosed() {
  tabs::TabInterface* placeholder = this->placeholder();
  still_tab_ = tabs::TabHandle::Null();
  still_image_ = nil;
  placeholder_ = tabs::TabHandle::Null();
  [bridge_ stillChanged];
  if (!placeholder || !space_tabs_) {
    return;
  }
  // D2: an ordinary new tab page at the top of the shown Space, with the
  // command bar.
  space_tabs_->ListPlaceholder(browser_->tab_strip_model(), placeholder);
  last_active_[shown_space_] = placeholder->GetHandle();
  came_from_ = tabs::TabHandle::Null();
  [clair_window_ showCommandBarWithMode:ClairCommandBarModeCurrentTab];
}

bool ClairBrowserWindow::HandTabsToAnotherWindow() {
  if (!space_tabs_ || !space_tabs_->is_regular() || detached_ ||
      browser_shutdown::IsTryingToQuit()) {
    return false;
  }
  // D4: the most recently active other regular window of the profile.
  ClairBrowserWindow* target = nullptr;
  ForEachCurrentBrowserWindowInterfaceOrderedByActivation(
      [this, &target](BrowserWindowInterface* candidate) {
        ClairBrowserWindow* window = FromBrowser(candidate);
        if (window && window != this && window->space_tabs_ == space_tabs_ &&
            !window->detached_ && !window->browser()->IsDeleteScheduled()) {
          target = window;
          return false;
        }
        return true;
      });
  if (!target) {
    return false;
  }
  // Each row with its Peek, the placeholder left out, the active row last so
  // Chromium picks this window's next tab only once.
  TabStripModel* strip = browser_->tab_strip_model();
  tabs::TabInterface* active = strip->GetActiveTab();
  tabs::TabInterface* active_row =
      active && peeks_ && peeks_->ParentOf(active) ? peeks_->ParentOf(active)
                                                   : active;
  std::vector<tabs::TabHandle> rows;
  for (int i = 0; i < strip->count(); ++i) {
    tabs::TabInterface* tab = strip->GetTabAtIndex(i);
    if (!tab || tab == active_row ||
        ClairSpaceTabs::IsPlaceholder(tab->GetContents()) ||
        (peeks_ && peeks_->ParentOf(tab))) {
      continue;
    }
    rows.push_back(tab->GetHandle());
  }
  if (active_row && !ClairSpaceTabs::IsPlaceholder(active_row->GetContents())) {
    rows.push_back(active_row->GetHandle());
  }
  if (rows.empty()) {
    return false;
  }
  for (const tabs::TabHandle& handle : rows) {
    if (tabs::TabInterface* row = handle.Get()) {
      target->MoveFamilyHere(this, row);
    }
  }
  // Emptied, the browser closes once Chromium is done with its strip; the
  // window goes now, so it can't become key meanwhile.
  if (browser_->tab_strip_model()->empty()) {
    [ns_window_ orderOut:nil];
  }
  // The other window showed a still of one of them: it shows the tab now.
  if (tabs::TabInterface* still = target->still_tab_.Get();
      still && HolderOf(still) == target) {
    target->ActivateRow(still);
  }
  return true;
}

void ClairBrowserWindow::ForgetFindBar() {
  find_bar_ = nullptr;
}

// --- Events from the NSWindow ---

void ClairBrowserWindow::WindowDidBecomeKey() {
  // A browser that's closing has left Chromium's list of browsers, which
  // CHECKs that an active one is in it. Its window can still become key, as
  // when it handed its tabs to another window (share-tabs-across-windows D4)
  // and AppKit orders a child window such as a tooltip.
  if (detached_ || browser_->IsDeleteScheduled() ||
      browser_->tab_strip_model()->empty()) {
    return;
  }
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  // add-spaces D1: the Space a new window shows.
  if (space_tabs_ && space_tabs_->is_regular()) {
    clair::ClairSpaceStore::Get()->SetLastSpace(shown_space_);
  }
  // share-tabs-across-windows D2: a window showing a still takes its tab
  // back, once AppKit has finished making it key. As in Arc, the click that
  // made it key reaches no row, so it doesn't wait for that click.
  if (still_tab_ != tabs::TabHandle::Null()) {
    PostTakeBack(weak_factory_.GetWeakPtr());
  }
}

void ClairBrowserWindow::WindowDidResignKey() {
  BrowserActiveStateManager::From(browser_)->DidBecomeInactive();
}

void ClairBrowserWindow::WindowGeometryChanged() {
  if (!IsFullscreen() && !IsMinimized() && !ns_window_.zoomed) {
    restored_bounds_ = gfx::ScreenRectFromNSRect(ns_window_.frame);
  }
  if (!IsFullscreen() && chrome::ShouldSaveWindowPlacement(browser_)) {
    chrome::SaveWindowPlacement(browser_, GetRestoredBounds(),
                                GetWindowShowState());
  }
  modal_dialog_host_.NotifyPositionRequiresUpdate();
}

bool ClairBrowserWindow::HandleExclusiveAccessKey(NSEvent* event) {
  if (!exclusive_access_context_.page_fullscreen() ||
      (event.type != NSEventTypeKeyDown && event.type != NSEventTypeKeyUp)) {
    return false;
  }
  if (exclusive_access_context_.DeferExitWhileEntering(event)) {
    return true;
  }
  return ExclusiveAccessManager::From(browser_)->HandleUserKeyEvent(
      input::NativeWebKeyboardEvent(gfx::NativeEvent(event)));
}

void ClairBrowserWindow::WindowFullscreenChanged(bool entered) {
  exclusive_access_context_.WindowFullscreenChanged(entered);
  WindowGeometryChanged();
}

void ClairBrowserWindow::WindowCloseRequested() {
  Close();
}

void ClairBrowserWindow::UpdateDevTools() {
  [clair_window_ devToolsDidChange];
}

void ClairBrowserWindow::ShowToast(const std::u16string& text) {
  [clair_window_ showToast:base::SysUTF16ToNSString(text)];
}

gfx::Rect ClairBrowserWindow::SiteControlsAnchorInScreen() const {
  id<ClairWindow> window = clair_window_;
  if (!window) {
    return gfx::Rect(GetBounds().origin(), gfx::Size());
  }
  const ClairAnchor anchor = [window anchorForKind:ClairAnchorKindSiteControls
                                         indicator:ClairTabIndicatorsNone
                                       extensionID:nil];
  return gfx::ScreenRectFromNSRect(
      [ns_window_ convertRectToScreen:anchor.rect]);
}

void ClairBrowserWindow::ZoomChanged(bool can_show_bubble) {
  if (!can_show_bubble) {
    return;
  }
  content::WebContents* active = browser_->tab_strip_model()->GetActiveWebContents();
  auto* zoom = active ? zoom::ZoomController::FromWebContents(active) : nullptr;
  if (!zoom) {
    return;
  }
  ShowToast(l10n_util::GetStringFUTF16(
      IDS_TOOLTIP_ZOOM, base::UTF8ToUTF16(base::StringPrintf(
                            "%d%%", zoom->GetZoomPercent()))));
}

// --- ui::BaseWindow ---

bool ClairBrowserWindow::IsActive() const {
  return ns_window_.keyWindow;
}

bool ClairBrowserWindow::IsMaximized() const {
  return ns_window_.zoomed;
}

bool ClairBrowserWindow::IsMinimized() const {
  return ns_window_.miniaturized;
}

bool ClairBrowserWindow::IsFullscreen() const {
  return (ns_window_.styleMask & NSWindowStyleMaskFullScreen) != 0;
}

gfx::NativeWindow ClairBrowserWindow::GetNativeWindow() const {
  return gfx::NativeWindow(ns_window_);
}

gfx::Rect ClairBrowserWindow::GetRestoredBounds() const {
  return restored_bounds_.IsEmpty() ? GetBounds() : restored_bounds_;
}

ui::mojom::WindowShowState ClairBrowserWindow::GetRestoredState() const {
  return IsMaximized() ? ui::mojom::WindowShowState::kMaximized
                       : ui::mojom::WindowShowState::kNormal;
}

gfx::Rect ClairBrowserWindow::GetBounds() const {
  return gfx::ScreenRectFromNSRect(ns_window_.frame);
}

void ClairBrowserWindow::Show() {
  // As BrowserView::Show(): the browser becomes the last active one now, not
  // when AppKit gets round to making the window key.
  BrowserActiveStateManager::From(browser_)->DidBecomeActive();
  const bool was_visible = ns_window_.visible;
  // Change 1's background-relaunch hook keeps this from bringing Clair
  // forward when it relaunched behind another app.
  [NSApp activateIgnoringOtherApps:YES];
  [ns_window_ makeKeyAndOrderFront:nil];
  if (!was_visible) {
    if (initial_show_state_ == ui::mojom::WindowShowState::kMaximized &&
        !ns_window_.zoomed) {
      [ns_window_ zoom:nil];
    } else if (initial_show_state_ == ui::mojom::WindowShowState::kMinimized) {
      [ns_window_ miniaturize:nil];
    } else if (initial_show_state_ == ui::mojom::WindowShowState::kFullscreen) {
      [ns_window_ toggleFullScreen:nil];
    }
    if (content::WebContents* active =
            browser_->tab_strip_model()->GetActiveWebContents()) {
      for (content::WebContents* page : PagesShownWith(active)) {
        page->UpdateWebContentsVisibility(content::Visibility::VISIBLE);
      }
      active->Focus();
    }
  }
}

void ClairBrowserWindow::Hide() {
  [ns_window_ orderOut:nil];
}

bool ClairBrowserWindow::IsVisible() const {
  return ns_window_.visible;
}

void ClairBrowserWindow::ShowInactive() {
  [ns_window_ orderFront:nil];
}

void ClairBrowserWindow::Close() {
  // share-tabs-across-windows D4: while another regular window of the
  // profile is open, the window's tabs move there and none closes. Moving
  // the last one empties the strip, and TabStripEmpty() closes the browser.
  if (!browser_->IsDeleteScheduled() && HandTabsToAnotherWindow() &&
      (browser_->tab_strip_model()->empty() || browser_->IsDeleteScheduled())) {
    return;
  }
  // add-peek D9: Peeks close with the window's other tabs; session restore
  // and Reopen Closed Window leave them out by their tag.
  // Chromium's close flow: beforeunload may veto it; then the tabs close, and
  // TabStripEmpty() calls this again for the empty browser, whose deletion
  // UnloadController then schedules. The browser is never deleted here.
  UnloadController::From(browser_)->OnWindowClosing();
  if (browser_->IsDeleteScheduled()) {
    DetachFromClairUI();
    [ns_window_ orderOut:nil];
  }
}

void ClairBrowserWindow::Activate() {
  [NSApp activateIgnoringOtherApps:YES];
  [ns_window_ makeKeyAndOrderFront:nil];
}

void ClairBrowserWindow::Deactivate() {
  [ns_window_ orderBack:nil];
}

void ClairBrowserWindow::Maximize() {
  if (!ns_window_.zoomed) {
    [ns_window_ zoom:nil];
  }
}

void ClairBrowserWindow::Minimize() {
  [ns_window_ miniaturize:nil];
}

void ClairBrowserWindow::Restore() {
  if (ns_window_.miniaturized) {
    [ns_window_ deminiaturize:nil];
  }
  if (ns_window_.zoomed) {
    [ns_window_ zoom:nil];
  }
}

void ClairBrowserWindow::SetBounds(const gfx::Rect& bounds) {
  if (IsFullscreen()) {
    return;
  }
  [ns_window_ setFrame:ToNSRect(bounds) display:YES];
}

void ClairBrowserWindow::FlashFrame(bool flash) {
  if (flash) {
    [NSApp requestUserAttention:NSInformationalRequest];
  }
}

ui::ZOrderLevel ClairBrowserWindow::GetZOrderLevel() const {
  return ns_window_.level > NSNormalWindowLevel
             ? ui::ZOrderLevel::kFloatingWindow
             : ui::ZOrderLevel::kNormal;
}

void ClairBrowserWindow::SetZOrderLevel(ui::ZOrderLevel order) {
  ns_window_.level = order == ui::ZOrderLevel::kNormal ? NSNormalWindowLevel
                                                       : NSFloatingWindowLevel;
}

// --- BrowserWindow ---

bool ClairBrowserWindow::IsOnCurrentWorkspace() const {
  return ns_window_.onActiveSpace;
}

bool ClairBrowserWindow::IsVisibleOnScreen() const {
  return (ns_window_.occlusionState & NSWindowOcclusionStateVisible) != 0;
}

void ClairBrowserWindow::SetTopControlsShownRatio(
    content::WebContents* web_contents,
    float ratio) {}

bool ClairBrowserWindow::DoBrowserControlsShrinkRendererSize(
    const content::WebContents* contents) const {
  return false;
}

ui::NativeTheme* ClairBrowserWindow::GetNativeTheme() {
  return ui::NativeTheme::GetInstanceForNativeUi();
}

const ui::ThemeProvider* ClairBrowserWindow::GetThemeProvider() const {
  return &ThemeService::GetThemeProviderForProfile(browser_->GetProfile());
}

const ui::ColorProvider* ClairBrowserWindow::GetColorProvider() const {
  return ui::ColorProviderManager::Get().GetColorProviderFor(
      ui::NativeTheme::GetInstanceForNativeUi()->GetColorProviderKey(nullptr,
                                                                     false));
}

int ClairBrowserWindow::GetTopControlsHeight() const {
  return 0;
}

void ClairBrowserWindow::SetTopControlsGestureScrollInProgress(
    bool in_progress) {}

std::vector<StatusBubble*> ClairBrowserWindow::GetStatusBubbles() {
  // Chromium treats every status bubble it gets here as a Views one
  // (BrowserWebContentsDelegate), so the native window's is reached through
  // the hook instead.
  return {};
}

void ClairBrowserWindow::SetStatusURL(const GURL& url) {
  status_bubble_.SetURL(url);
}

void ClairBrowserWindow::UpdateTitleBar() {
  // The title isn't drawn, but the Window menu and Mission Control show it.
  if (auto* metadata = WindowMetadataController::From(browser_)) {
    ns_window_.title = base::SysUTF16ToNSString(
        metadata->GetWindowTitleForCurrentTab(/*include_app_name=*/false));
  }
}

void ClairBrowserWindow::UpdateLoadingAnimations(bool is_visible) {
  if (content::WebContents* active =
          browser_->tab_strip_model()->GetActiveWebContents()) {
    [bridge_ tabChanged:active];
  }
}

void ClairBrowserWindow::OnActiveTabChanged(content::WebContents* old_contents,
                                            content::WebContents* new_contents,
                                            int index,
                                            int reason) {
  // A tab created in the background has never been sized; give it the
  // outgoing tab's size so its first layout isn't at zero.
  if (old_contents && new_contents->GetSize().IsEmpty()) {
    const gfx::Size size = old_contents->GetContainerBounds().size();
    if (!size.IsEmpty()) {
      new_contents->Resize(gfx::Rect(size));
    }
  }
  // add-spaces D3: the window shows the active tab's Space. Chromium tells
  // the window before the lists hear of a new tab: a restored one already
  // carries its Space, and a new one joins the shown Space.
  tabs::TabInterface* new_tab =
      tabs::TabInterface::MaybeGetFromContents(new_contents);
  // share-tabs-across-windows D2: the placeholder under a still is in no
  // Space, and leaves the shown Space and the came-from row alone.
  if (inserting_placeholder_) {
    ClairSpaceTabs::MarkPlaceholder(new_contents);
    if (new_tab) {
      placeholder_ = new_tab->GetHandle();
    }
  }
  const bool new_is_placeholder = ClairSpaceTabs::IsPlaceholder(new_contents);
  const bool old_is_placeholder =
      old_contents && ClairSpaceTabs::IsPlaceholder(old_contents);
  if (space_tabs_ && new_tab && !new_is_placeholder) {
    const std::string space = space_tabs_->IntendedSpaceOf(new_tab);
    if (!space.empty() && space != shown_space_) {
      SetShownSpace(space);
    }
    last_active_[shown_space_] = new_tab->GetHandle();
  }
  // D4: the row the user came from, unless a close or Clair's own choice
  // changed the active tab.
  tabs::TabInterface* old_tab =
      old_contents ? tabs::TabInterface::MaybeGetFromContents(old_contents)
                   : nullptr;
  const bool old_closed =
      !old_tab || browser_->tab_strip_model()->GetIndexOfTab(old_tab) ==
                      TabStripModel::kNoTab;
  if (new_is_placeholder) {
    // The still keeps the row the user came to it from.
  } else if (old_is_placeholder) {
    // Taking the still's tab back keeps it too; moving on forgets it.
    tabs::TabInterface* still = still_tab_.Get();
    if (!still || !new_tab || RowOf(new_tab) != still) {
      came_from_ = tabs::TabHandle::Null();
    }
  } else if (choosing_next_ || old_closed) {
    came_from_ = tabs::TabHandle::Null();
  } else if (new_tab) {
    tabs::TabInterface* row =
        peeks_ && peeks_->ParentOf(old_tab) ? peeks_->ParentOf(old_tab)
                                            : old_tab;
    const bool same_family =
        row == new_tab || (peeks_ && peeks_->ParentOf(new_tab) == row);
    if (!same_family) {
      came_from_ = row->GetHandle();
    }
  }
  // D2: another tab became active, which ends the still: the still's tab came
  // back, or the user selected another row or Space.
  if (!new_is_placeholder && still_tab_ != tabs::TabHandle::Null()) {
    EndStill();
  }
  // D2: the row shown until now goes back to a window with a still of it,
  // if no window shows it once the strip is done.
  if (old_tab && !old_closed && !old_is_placeholder) {
    tabs::TabInterface* old_row = RowOf(old_tab);
    if (!new_tab || RowOf(new_tab) != old_row) {
      base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
          FROM_HERE, base::BindOnce(&GiveBackToStill, old_row->GetHandle()));
    }
  }
  // ClairUI swaps the page in the card now, before visibility changes.
  [bridge_ activeTabChanged];
  // As WebUIBrowserWindow: the old page reports hidden, the new one the
  // window's visibility. A tab and its Peek show together (add-peek D4).
  const std::set<content::WebContents*> shown = PagesShownWith(new_contents);
  if (old_contents) {
    for (content::WebContents* page : PagesShownWith(old_contents)) {
      if (!shown.contains(page)) {
        page->UpdateWebContentsVisibility(content::Visibility::HIDDEN);
      }
    }
  }
  for (content::WebContents* page : shown) {
    page->UpdateWebContentsVisibility(IsVisible() ? content::Visibility::VISIBLE
                                                  : content::Visibility::HIDDEN);
  }
  if (extensions_) {
    extensions_->ActiveTabChanged();
  }
  UpdateDevTools();
  UpdateTitleBar();
  // As BrowserView: the page takes focus when its tab becomes active in the
  // key window.
  if (IsActive()) {
    new_contents->RestoreFocus();
  }
}

void ClairBrowserWindow::OnTabDetached(content::WebContents* contents,
                                       bool was_active) {}

gfx::Size ClairBrowserWindow::GetContentsSize() const {
  id<ClairWindow> window = clair_window_;
  NSView* view = window ? window.pageContainerView : ns_window_.contentView;
  return view ? gfx::Size(NSWidth(view.bounds), NSHeight(view.bounds))
              : gfx::Size();
}

void ClairBrowserWindow::SetContentsSize(const gfx::Size& size) {
  const gfx::Size current = GetContentsSize();
  NSRect frame = ns_window_.frame;
  const CGFloat dw = size.width() - current.width();
  const CGFloat dh = size.height() - current.height();
  frame.size.width += dw;
  frame.size.height += dh;
  frame.origin.y -= dh;
  [ns_window_ setFrame:frame display:YES];
}

autofill::AutofillBubbleHandler* ClairBrowserWindow::GetAutofillBubbleHandler() {
  return autofill_bubble_handler_.get();
}

LocationBar* ClairBrowserWindow::GetLocationBar() const {
  return const_cast<ClairLocationBar*>(&location_bar_);
}

ui::AcceleratorProvider* ClairBrowserWindow::GetAcceleratorProvider() {
  return nullptr;
}

PinnedToolbarActions* ClairBrowserWindow::GetPinnedToolbarActions() {
  return nullptr;
}

void ClairBrowserWindow::SetFocusToLocationBar(bool is_user_initiated) {
  // Cmd+L: the command bar on the current URL (D10). Chromium also asks for
  // the location bar on its own, as when a new tab page loads, which would
  // open the command bar over every new window; that keeps the page focused.
  if (!is_user_initiated) {
    return;
  }
  [clair_window_ showCommandBarWithMode:ClairCommandBarModeCurrentTab];
}

void ClairBrowserWindow::UpdateReloadStopState(bool is_loading, bool force) {
  UpdateLoadingAnimations(true);
}

void ClairBrowserWindow::UpdateToolbar(content::WebContents* contents) {
  content::WebContents* tab =
      contents ? contents : browser_->tab_strip_model()->GetActiveWebContents();
  if (tab) {
    [bridge_ tabChanged:tab];
  }
}

bool ClairBrowserWindow::UpdateToolbarSecurityState() {
  UpdateToolbar(nullptr);
  return true;
}

void ClairBrowserWindow::UpdateCustomTabBarVisibility(bool visible,
                                                      bool animate) {}
void ClairBrowserWindow::ResetToolbarTabState(content::WebContents* contents) {}
void ClairBrowserWindow::FocusToolbar() {}
void ClairBrowserWindow::ToolbarSizeChanged(bool is_animating) {}
void ClairBrowserWindow::TabDraggingStatusChanged(bool is_dragging) {}
void ClairBrowserWindow::LinkOpeningFromGesture(
    WindowOpenDisposition disposition) {}

void ClairBrowserWindow::FocusAppMenu() {
  LogUnavailable("The app menu");
}

bool ClairBrowserWindow::IsTabStripEditable() const {
  return true;
}

void ClairBrowserWindow::DisableTabStripEditingForTesting() {}

bool ClairBrowserWindow::IsToolbarVisible() const {
  // The sidebar is the toolbar: chrome.action.openPopup() checks this.
  return true;
}

bool ClairBrowserWindow::IsToolbarShowing() const {
  return false;
}

// The URL field and the command bar stand in for the location bar. Chromium
// focuses the location bar for Cmd+L and File > Open Location only while it's
// visible (browser_command_controller.cc, browser_actions.cc).
bool ClairBrowserWindow::IsLocationBarVisible() const {
  return true;
}

void ClairBrowserWindow::ShowUpdateChromeDialog() {}

void ClairBrowserWindow::ShowIntentPickerBubble(
    std::vector<apps::IntentPickerAppInfo> app_info,
    bool show_stay_in_chrome,
    bool show_remember_selection,
    apps::IntentPickerBubbleType bubble_type,
    const std::optional<url::Origin>& initiating_origin,
    IntentPickerResponse callback) {
  LogUnavailable("The intent picker");
  std::move(callback).Run(std::string(), apps::PickerEntryType::kUnknown,
                          apps::IntentPickerCloseReason::STAY_IN_CHROME,
                          false);
}

void ClairBrowserWindow::ShowBookmarkBubble(const GURL& url,
                                            bool already_bookmarked) {
  // D10: no bookmarks in the interface.
  LogUnavailable("The bookmark bubble");
}

ShowTranslateBubbleResult ClairBrowserWindow::ShowTranslateBubble(
    content::WebContents* contents,
    translate::TranslateStep step,
    const std::string& source_language,
    const std::string& target_language,
    translate::TranslateErrors error_type,
    bool is_user_gesture) {
  LogUnavailable("Translate");
  return ShowTranslateBubbleResult::kBrowserWindowNotValid;
}

DownloadBubbleUIController* ClairBrowserWindow::GetDownloadBubbleUIController() {
  return nullptr;
}

void ClairBrowserWindow::ConfirmBrowserCloseWithPendingDownloads(
    int download_count,
    DownloadCloseType dialog_type,
    base::OnceCallback<void(bool)> callback) {
  DownloadInProgressDialogView::Show(GetNativeWindow(), download_count,
                                     dialog_type, std::move(callback));
}

void ClairBrowserWindow::ShowAppMenu() {
  LogUnavailable("The app menu");
}

void ClairBrowserWindow::PreHandleDragUpdate(const content::DropData& drop_data,
                                             const gfx::PointF& point) {}
void ClairBrowserWindow::PreHandleDragExit() {}
void ClairBrowserWindow::HandleDragEnded() {}

content::KeyboardEventProcessingResult
ClairBrowserWindow::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  // As BrowserNativeWidgetMac: key equivalents with modifiers were offered to
  // CommandDispatcher already; the page may have them first unless they're a
  // browser shortcut.
  // add-peek D6: Esc while Confirm shows closes the Peek before the page
  // sees it.
  if (peeks_) {
    const content::KeyboardEventProcessingResult result =
        peeks_->PreHandleKeyboardEvent(event);
    if (result != content::KeyboardEventProcessingResult::NOT_HANDLED) {
      return result;
    }
  }
  NSEvent* ns_event = event.os_event.Get();
  if (ns_event && EventUsesPerformKeyEquivalent(ns_event)) {
    int command = CommandForKeyEvent(ns_event).chrome_command;
    if (command == -1) {
      command = DelayedWebContentsCommandForKeyEvent(ns_event);
    }
    if (command != -1) {
      return content::KeyboardEventProcessingResult::NOT_HANDLED_IS_SHORTCUT;
    }
  }
  return content::KeyboardEventProcessingResult::NOT_HANDLED;
}

bool ClairBrowserWindow::HandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  if (!ShouldHandleKeyboardEvent(event)) {
    return false;
  }
  // add-peek D6: an Esc the Peek's page didn't use closes the Peek.
  if (peeks_ && peeks_->HandleKeyboardEvent(event)) {
    return true;
  }
  // Gives CommandDispatcher the chance to finish passing the key on.
  return [[ns_window_ commandDispatcher] redispatchKeyEvent:event.os_event.Get()];
}

std::unique_ptr<FindBar> ClairBrowserWindow::CreateFindBar() {
  auto find_bar = std::make_unique<ClairFindBar>(this);
  find_bar_ = find_bar.get();
  return find_bar;
}

web_modal::WebContentsModalDialogHost*
ClairBrowserWindow::GetWebContentsModalDialogHost() {
  return &modal_dialog_host_;
}

web_modal::WebContentsModalDialogHost*
ClairBrowserWindow::GetWebContentsModalDialogHostFor(
    content::WebContents* web_contents) {
  return &modal_dialog_host_;
}

void ClairBrowserWindow::ShowAvatarBubbleFromAvatarButton(
    bool is_source_accelerator) {
  LogUnavailable("The profile menu");
}

void ClairBrowserWindow::MaybeShowProfileSwitchIPH() {}
void ClairBrowserWindow::MaybeShowSupervisedUserProfileSignInIPH() {}

void ClairBrowserWindow::ShowHatsDialog(
    const std::string& site_id,
    const std::optional<std::string>& hats_histogram_name,
    const std::optional<uint64_t> hats_survey_ukm_id,
    base::OnceClosure success_callback,
    base::OnceClosure failure_callback,
    const SurveyBitsData& product_specific_bits_data,
    const SurveyStringData& product_specific_string_data) {
  std::move(failure_callback).Run();
}

ExclusiveAccessContext* ClairBrowserWindow::GetExclusiveAccessContext() {
  return &exclusive_access_context_;
}

std::string ClairBrowserWindow::GetWorkspace() const {
  return std::string();
}

bool ClairBrowserWindow::IsVisibleOnAllWorkspaces() const {
  return false;
}

void ClairBrowserWindow::ShowEmojiPanel() {
  [NSApp orderFrontCharacterPalette:nil];
}

std::unique_ptr<content::EyeDropper> ClairBrowserWindow::OpenEyeDropper(
    content::RenderFrameHost* frame,
    content::EyeDropperListener* listener) {
  // Null makes the page's EyeDropper.open() reject.
  LogUnavailable("The EyeDropper");
  return nullptr;
}

void ClairBrowserWindow::ShowCaretBrowsingDialog() {
  LogUnavailable("The caret browsing dialog");
}

void ClairBrowserWindow::CreateTabSearchBubble() {
  LogUnavailable("Tab search");
}

void ClairBrowserWindow::CloseTabSearchBubble() {}

void ClairBrowserWindow::ShowIncognitoClearBrowsingDataDialog() {
  LogUnavailable("The incognito clear browsing data dialog");
}

void ClairBrowserWindow::ShowIncognitoHistoryDisclaimerDialog() {
  LogUnavailable("The incognito history disclaimer");
}

bool ClairBrowserWindow::IsUnframedModeEnabled() const {
  return false;
}

bool ClairBrowserWindow::GetCanResize() {
  return true;
}

ui::mojom::WindowShowState ClairBrowserWindow::GetWindowShowState() const {
  if (IsFullscreen()) {
    return ui::mojom::WindowShowState::kFullscreen;
  }
  if (IsMinimized()) {
    return ui::mojom::WindowShowState::kMinimized;
  }
  if (IsMaximized()) {
    return ui::mojom::WindowShowState::kMaximized;
  }
  return ui::mojom::WindowShowState::kNormal;
}

void ClairBrowserWindow::ShowChromeLabs() {
  LogUnavailable("Chrome Labs");
}

BrowserView* ClairBrowserWindow::AsBrowserView() {
  return nullptr;
}

void ClairBrowserWindow::DeleteBrowserWindow() {
  delete this;
}
