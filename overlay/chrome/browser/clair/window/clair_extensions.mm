// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.
//
// The popup host follows Crest's native ExtensionView bridge (pauljoda/Crest,
// MPL-2.0), itself after Mori's (MIT); see CREDITS.md.

#include "chrome/browser/clair/window/clair_extensions.h"

#include <algorithm>
#include <tuple>
#include <utility>
#include <vector>

#include "base/logging.h"
#include "base/strings/string_util.h"
#include "base/strings/sys_string_conversions.h"
#include "base/strings/utf_string_conversions.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/clair/window/clair_window_hooks.h"
#include "chrome/browser/extensions/extension_install_prompt_show_params.h"
#include "chrome/browser/extensions/extension_action_runner.h"
#include "chrome/browser/extensions/extension_context_menu_model.h"
#include "chrome/browser/extensions/extension_view.h"
#include "chrome/browser/extensions/extension_view_host.h"
#include "chrome/browser/extensions/extension_view_host_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "components/input/native_web_keyboard_event.h"
#include "components/sessions/content/session_tab_helper.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host_view.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/extension_action.h"
#include "extensions/browser/extension_action_manager.h"
#include "extensions/browser/extension_host.h"
#include "extensions/browser/extension_host_observer.h"
#include "extensions/browser/install_prompt_data.h"
#include "extensions/browser/install_prompt_permissions.h"
#include "extensions/browser/ui_util.h"
#include "extensions/common/api/extension_action/action_info.h"
#include "extensions/common/extension.h"
#include "skia/ext/skia_utils_mac.h"
#include "ui/gfx/image/image.h"
#include "ui/gfx/image/image_skia.h"
#import "ui/menus/cocoa/menu_controller.h"

// --- Snapshots ---------------------------------------------------------------

@interface ClairChromiumExtensionAction : NSObject <ClairExtensionAction>
@property(nonatomic, copy) NSString* extensionID;
@property(nonatomic, copy) NSString* name;
@property(nonatomic, nullable) NSImage* icon;
@property(nonatomic, copy) NSString* badgeText;
@property(nonatomic, nullable) NSColor* badgeBackgroundColor;
@property(nonatomic) BOOL isPinned;
@property(nonatomic) BOOL isEnabled;
@property(nonatomic) BOOL hasPopup;
@end

@implementation ClairChromiumExtensionAction
@end

@interface ClairChromiumExtensionPrompt : NSObject <ClairExtensionPrompt>
@property(nonatomic) NSInteger promptID;
@property(nonatomic) ClairExtensionPromptKind kind;
@property(nonatomic, copy) NSString* extensionName;
@property(nonatomic, nullable) NSImage* icon;
@property(nonatomic, copy) NSArray<NSString*>* permissions;
@property(nonatomic, copy) NSString* title;
@property(nonatomic, copy) NSString* permissionsHeading;
@property(nonatomic, copy) NSString* acceptLabel;
@property(nonatomic, copy) NSString* cancelLabel;
@end

@implementation ClairChromiumExtensionPrompt
- (instancetype)init {
  if ((self = [super init])) {
    _extensionName = @"";
    _permissions = @[];
    _title = @"";
    _permissionsHeading = @"";
    _acceptLabel = @"";
    _cancelLabel = @"";
  }
  return self;
}
@end

// --- The popup ---------------------------------------------------------------

// An action's popup page. Chromium owns the page; ClairUI shows its view
// attached to the clicked button and follows its auto-resize (25×25 to
// 800×600, as Chromium's popups do).
class ClairExtensions::Popup : public extensions::ExtensionView,
                               public extensions::ExtensionHostObserver {
 public:
  Popup(ClairExtensions* owner,
        std::unique_ptr<extensions::ExtensionViewHost> host,
        std::string extension_id,
        ClairAnchorKind anchor,
        ShowPopupCallback callback)
      : owner_(owner),
        host_(std::move(host)),
        extension_id_(std::move(extension_id)),
        anchor_(anchor),
        callback_(std::move(callback)) {
    host_->set_view(this);
    host_->AddObserver(this);
    host_->SetCloseHandler(base::BindOnce(
        [](base::WeakPtr<Popup> popup, extensions::ExtensionHost*) {
          // The page called window.close(), or its extension unloaded.
          if (popup) {
            popup->owner_->ClosePopup();
          }
        },
        weak_factory_.GetWeakPtr()));
    host_->CreateRendererSoon();
  }

  ~Popup() override {
    if (callback_) {
      std::move(callback_).Run(nullptr);
    }
    if (host_) {
      host_->RemoveObserver(this);
      host_->set_view(nullptr);
    }
  }

  const std::string& extension_id() const { return extension_id_; }

  // extensions::ExtensionView:
  gfx::NativeView GetNativeView() override {
    return host_ ? host_->host_contents()->GetNativeView() : gfx::NativeView();
  }

  void ResizeDueToAutoResize(content::WebContents* web_contents,
                             const gfx::Size& new_size) override {
    size_ = NSMakeSize(std::clamp(new_size.width(), 25, 800),
                       std::clamp(new_size.height(), 25, 600));
    if (shown_) {
      [owner_->window_->clair_window() extensionPopupDidResize:size_];
    }
  }

  void RenderFrameCreated(content::RenderFrameHost* render_frame_host) override {
    if (content::RenderWidgetHostView* view = render_frame_host->GetView()) {
      view->EnableAutoResize(gfx::Size(25, 25), gfx::Size(800, 600));
    }
  }

  bool HandleKeyboardEvent(content::WebContents* source,
                           const input::NativeWebKeyboardEvent& event) override {
    // Keys the page didn't use, such as Copy and Paste, go to the menu bar, as
    // a tab's do.
    NSEvent* native_event = event.os_event.Get();
    if (event.GetType() != input::NativeWebKeyboardEvent::Type::kRawKeyDown ||
        !native_event || native_event.type != NSEventTypeKeyDown) {
      return false;
    }
    return [NSApp.mainMenu performKeyEquivalent:native_event];
  }

  void OnLoaded() override {
    if (shown_ || !host_) {
      return;
    }
    id<ClairWindow> window = owner_->window_->clair_window();
    NSView* view = host_->host_contents()->GetNativeView().GetNativeNSView();
    if (!window || !view) {
      owner_->ClosePopup();
      return;
    }
    shown_ = true;
    [window showExtensionPopup:view
                          size:size_
                     extension:base::SysUTF8ToNSString(extension_id_)
                        anchor:anchor_];
    host_->host_contents()->Focus();
    if (callback_) {
      std::move(callback_).Run(host_.get());
    }
  }

  // extensions::ExtensionHostObserver:
  void OnExtensionHostDestroyed(extensions::ExtensionHost* host) override {
    if (host_.get() == host) {
      // The host is going away on its own; don't destroy it again.
      std::ignore = host_.release();
    }
    owner_->ClosePopup();
  }

 private:
  const raw_ptr<ClairExtensions> owner_;
  std::unique_ptr<extensions::ExtensionViewHost> host_;
  const std::string extension_id_;
  const ClairAnchorKind anchor_;
  ShowPopupCallback callback_;
  NSSize size_ = NSMakeSize(320, 240);
  bool shown_ = false;
  base::WeakPtrFactory<Popup> weak_factory_{this};
};

// --- ClairExtensions ---------------------------------------------------------

ClairExtensions::ClairExtensions(ClairBrowserWindow* window) : window_(window) {
  Profile* profile = window_->browser()->GetProfile();
  if (ToolbarActionsModel* model = ToolbarActionsModel::Get(profile)) {
    model_observation_.Observe(model);
  }
  if (auto* dispatcher = extensions::ExtensionActionDispatcher::Get(profile)) {
    dispatcher_observation_.Observe(dispatcher);
  }
  registry_observation_.Observe(extensions::ExtensionRegistry::Get(profile));
  scoped_user_data_ =
      std::make_unique<ui::ScopedUnownedUserData<ExtensionsContainer>>(
          window_->browser()->GetUnownedUserDataHost(), *this);
}

ClairExtensions::~ClairExtensions() {
  context_menu_controller_ = nil;
  context_menu_.reset();
  popup_.reset();
  scoped_user_data_.reset();
  // The window is closing: anything it was asking counts as a cancel.
  std::map<int, base::OnceCallback<void(bool)>> prompts = std::move(prompts_);
  prompts_.clear();
  for (auto& [prompt_id, answer] : prompts) {
    std::move(answer).Run(false);
  }
}

NSArray<id<ClairExtensionAction>>* ClairExtensions::Snapshot() {
  Profile* profile = window_->browser()->GetProfile();
  ToolbarActionsModel* model = ToolbarActionsModel::Get(profile);
  if (!model || !model->actions_initialized()) {
    return @[];
  }
  content::WebContents* active =
      window_->browser()->tab_strip_model()->GetActiveWebContents();
  const int tab_id =
      active ? sessions::SessionTabHelper::IdForTab(active).id()
             : extensions::ExtensionAction::kDefaultTabId;
  auto* registry = extensions::ExtensionRegistry::Get(profile);
  auto* actions = extensions::ExtensionActionManager::Get(profile);

  std::vector<ToolbarActionsModel::ActionId> ids = model->pinned_action_ids();
  std::vector<ToolbarActionsModel::ActionId> unpinned;
  for (const auto& id : model->action_ids()) {
    if (!model->IsActionPinned(id)) {
      unpinned.push_back(id);
    }
  }
  std::ranges::sort(unpinned, [&](const auto& a, const auto& b) {
    const extensions::Extension* ea = registry->enabled_extensions().GetByID(a);
    const extensions::Extension* eb = registry->enabled_extensions().GetByID(b);
    return (ea ? ea->name() : a) < (eb ? eb->name() : b);
  });
  ids.insert(ids.end(), unpinned.begin(), unpinned.end());

  NSMutableArray<id<ClairExtensionAction>>* snapshot = [NSMutableArray array];
  for (const auto& id : ids) {
    const extensions::Extension* extension =
        registry->enabled_extensions().GetByID(id);
    extensions::ExtensionAction* action =
        extension ? actions->GetExtensionAction(*extension) : nullptr;
    if (!action) {
      continue;
    }
    ClairChromiumExtensionAction* item = [[ClairChromiumExtensionAction alloc] init];
    item.extensionID = base::SysUTF8ToNSString(id);
    const std::string title = action->GetTitle(tab_id);
    item.name = base::SysUTF8ToNSString(title.empty() ? extension->name() : title);
    if (extensions::IconImage* default_icon = action->default_icon_image();
        default_icon && !icon_observations_.IsObservingSource(default_icon)) {
      icon_observations_.AddObservation(default_icon);
    }
    gfx::Image icon = action->GetExplicitlySetIcon(tab_id);
    if (icon.IsEmpty()) {
      icon = action->GetDeclarativeIcon(tab_id);
    }
    if (icon.IsEmpty()) {
      icon = action->GetDefaultIconImage();
    }
    item.icon = icon.IsEmpty() ? nil : icon.ToNSImage();
    item.badgeText = base::SysUTF8ToNSString(action->GetDisplayBadgeText(tab_id));
    item.badgeBackgroundColor =
        skia::SkColorToSRGBNSColor(action->GetBadgeBackgroundColor(tab_id));
    item.isPinned = model->IsActionPinned(id);
    item.isEnabled = action->GetIsVisible(tab_id);
    item.hasPopup = action->HasPopup(tab_id);
    [snapshot addObject:item];
  }
  return snapshot;
}

void ClairExtensions::Run(const std::string& extension_id,
                          ClairAnchorKind anchor) {
  Browser* browser = window_->browser();
  Profile* profile = browser->GetProfile();
  content::WebContents* active = browser->tab_strip_model()->GetActiveWebContents();
  const extensions::Extension* extension =
      extensions::ExtensionRegistry::Get(profile)->enabled_extensions().GetByID(
          extension_id);
  auto* runner = active ? extensions::ExtensionActionRunner::GetForWebContents(active)
                        : nullptr;
  if (!extension || !runner) {
    return;
  }
  // A second click on the button whose popup is open closes it.
  if (popup_ && popup_->extension_id() == extension_id) {
    ClosePopup();
    return;
  }
  const auto result = runner->RunAction(extension, /*grant_tab_permissions=*/true);
  if (result == extensions::ExtensionAction::ShowAction::kShowPopup) {
    OpenPopup(extension_id, anchor, ShowPopupCallback());
  }
}

bool ClairExtensions::OpenPopup(const std::string& extension_id,
                                ClairAnchorKind anchor,
                                ShowPopupCallback callback) {
  Browser* browser = window_->browser();
  Profile* profile = browser->GetProfile();
  content::WebContents* active = browser->tab_strip_model()->GetActiveWebContents();
  const extensions::Extension* extension =
      extensions::ExtensionRegistry::Get(profile)->enabled_extensions().GetByID(
          extension_id);
  extensions::ExtensionAction* action =
      extension
          ? extensions::ExtensionActionManager::Get(profile)->GetExtensionAction(
                *extension)
          : nullptr;
  if (!action || !active) {
    return false;
  }
  const int tab_id = sessions::SessionTabHelper::IdForTab(active).id();
  if (!action->HasPopup(tab_id)) {
    return false;
  }
  std::unique_ptr<extensions::ExtensionViewHost> host =
      extensions::ExtensionViewHostFactory::CreatePopupHost(
          *extension, action->GetPopupUrl(tab_id), browser);
  if (!host) {
    return false;
  }
  ClosePopup();
  popup_ = std::make_unique<Popup>(this, std::move(host), extension_id, anchor,
                                   std::move(callback));
  return true;
}

void ClairExtensions::ClosePopup() {
  if (!popup_) {
    return;
  }
  popup_.reset();
  [window_->clair_window() closeExtensionPopup];
}

void ClairExtensions::SetPinned(const std::string& extension_id, bool pinned) {
  ToolbarActionsModel* model =
      ToolbarActionsModel::Get(window_->browser()->GetProfile());
  if (model && model->HasAction(extension_id) &&
      !model->IsActionForcePinned(extension_id)) {
    model->SetActionVisibility(extension_id, pinned);
  }
}

void ClairExtensions::PopupClosedByUser() {
  popup_.reset();
}

void ClairExtensions::ActiveTabChanged() {
  ClosePopup();
  Changed();
}

NSMenu* ClairExtensions::ContextMenu(const std::string& extension_id) {
  Browser* browser = window_->browser();
  Profile* profile = browser->GetProfile();
  ToolbarActionsModel* model = ToolbarActionsModel::Get(profile);
  const extensions::Extension* extension =
      extensions::ExtensionRegistry::Get(profile)->enabled_extensions().GetByID(
          extension_id);
  if (!model || !extension) {
    return nil;
  }
  // No PopupDelegate: Inspect Popup needs a popup that outlives losing focus.
  // Always kToolbarAction, even for a list row: kMenuItem drops Pin/Unpin,
  // because Chromium's own extensions menu has a separate pin button.
  auto menu_model = std::make_unique<extensions::ExtensionContextMenuModel>(
      extension, browser, model->IsActionPinned(extension_id),
      /*delegate=*/nullptr, /*can_show_icon_in_toolbar=*/true,
      extensions::ExtensionContextMenuModel::ContextMenuSource::kToolbarAction);
  // The controller refers to its model, so it goes first.
  context_menu_controller_ =
      [[MenuControllerCocoa alloc] initWithModel:menu_model.get()
                                   isContextMenu:YES
                                        delegate:nil];
  context_menu_ = std::move(menu_model);
  return context_menu_controller_.menu;
}

void ClairExtensions::ShowPrompt(id<ClairExtensionPrompt> prompt,
                                 base::OnceCallback<void(bool)> answer) {
  prompts_[static_cast<int>(prompt.promptID)] = std::move(answer);
  [window_->clair_window() showExtensionPrompt:prompt];
}

void ClairExtensions::AnswerPrompt(int prompt_id, bool accepted) {
  auto it = prompts_.find(prompt_id);
  if (it == prompts_.end()) {
    return;
  }
  base::OnceCallback<void(bool)> answer = std::move(it->second);
  prompts_.erase(it);
  std::move(answer).Run(accepted);
}

void ClairExtensions::DismissPrompt(int prompt_id) {
  if (prompts_.erase(prompt_id)) {
    [window_->clair_window() dismissExtensionPrompt:prompt_id];
  }
}

void ClairExtensions::PinNewExtension(const extensions::Extension& extension) {
  Profile* profile = window_->browser()->GetProfile();
  ToolbarActionsModel* model = ToolbarActionsModel::Get(profile);
  // Not ExtensionActionManager: this runs before the extension is enabled,
  // and it has no action for an extension that isn't.
  if (!model || !extensions::ActionInfo::GetExtensionActionInfo(&extension)) {
    return;
  }
  if (model->HasAction(extension.id())) {
    SetPinned(extension.id(), true);
  } else {
    // Chromium's own post-install path waits for the action the same way.
    pending_pins_.insert(extension.id());
  }
}

// ExtensionsContainer:

ToolbarActionViewModel* ClairExtensions::GetActionForId(
    const std::string& action_id) {
  return nullptr;
}

void ClairExtensions::HideActivePopup() {
  ClosePopup();
}

void ClairExtensions::CloseExtensionsMenuIfOpen() {}

bool ClairExtensions::ShowToolbarActionPopupForAPICall(
    const std::string& action_id,
    ShowPopupCallback callback) {
  ToolbarActionsModel* model =
      ToolbarActionsModel::Get(window_->browser()->GetProfile());
  const ClairAnchorKind anchor = model && model->IsActionPinned(action_id)
                                     ? ClairAnchorKindExtensionAction
                                     : ClairAnchorKindSiteControls;
  return OpenPopup(action_id, anchor, std::move(callback));
}

void ClairExtensions::ToggleExtensionsMenu() {}

bool ClairExtensions::HasAnyExtensions() const {
  ToolbarActionsModel* model =
      ToolbarActionsModel::Get(window_->browser()->GetProfile());
  return model && !model->action_ids().empty();
}

// Observers:

void ClairExtensions::OnToolbarActionAdded(
    const ToolbarActionsModel::ActionId& id) {
  if (pending_pins_.erase(id)) {
    // Not from here: pinning notifies the model's observers, and the model is
    // still iterating over them.
    base::WeakPtr<ClairExtensions> weak = weak_factory_.GetWeakPtr();
    std::string pinned_id = id;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (weak) {
        weak->SetPinned(pinned_id, true);
      }
    });
  }
  Changed();
}

void ClairExtensions::OnToolbarActionRemoved(
    const ToolbarActionsModel::ActionId& id) {
  if (popup_ && popup_->extension_id() == id) {
    ClosePopup();
  }
  Changed();
}

void ClairExtensions::OnToolbarActionUpdated(
    const ToolbarActionsModel::ActionId& id) {
  Changed();
}

void ClairExtensions::OnToolbarModelInitialized() {
  Changed();
}

void ClairExtensions::OnToolbarPinnedActionsChanged() {
  Changed();
}

void ClairExtensions::OnToolbarActionsModelShutdown() {
  model_observation_.Reset();
}

void ClairExtensions::OnExtensionActionUpdated(
    extensions::ExtensionAction* extension_action,
    content::WebContents* web_contents,
    content::BrowserContext* browser_context) {
  Changed();
}

void ClairExtensions::OnShuttingDown() {
  dispatcher_observation_.Reset();
}

void ClairExtensions::OnExtensionLoaded(content::BrowserContext* browser_context,
                                        const extensions::Extension* extension) {
  Changed();
}

void ClairExtensions::OnExtensionUnloaded(
    content::BrowserContext* browser_context,
    const extensions::Extension* extension,
    extensions::UnloadedExtensionReason reason) {
  if (popup_ && popup_->extension_id() == extension->id()) {
    ClosePopup();
  }
  pending_pins_.erase(extension->id());
  Changed();
}

void ClairExtensions::OnExtensionIconImageChanged(
    extensions::IconImage* image) {
  Changed();
}

void ClairExtensions::OnExtensionIconImageDestroyed(
    extensions::IconImage* image) {
  icon_observations_.RemoveObservation(image);
}

// Changes come in bursts while the registry and the toolbar model change, so
// they're posted once the turn ends.
void ClairExtensions::Changed() {
  if (flush_posted_) {
    return;
  }
  flush_posted_ = true;
  base::WeakPtr<ClairExtensions> weak = weak_factory_.GetWeakPtr();
  dispatch_async(dispatch_get_main_queue(), ^{
    if (weak) {
      weak->Flush();
    }
  });
}

void ClairExtensions::Flush() {
  flush_posted_ = false;
  if (id<ClairWindow> window = window_->clair_window()) {
    [window extensionActionsDidChange:Snapshot()];
  }
}

// --- The hooks (arc-extension-experience D4, D5) ---

namespace {

// The native window a dialog parented to `parent` belongs to. A popup window
// is a child of its browser window, so its prompts go on the browser window.
ClairBrowserWindow* WindowForNativeWindow(gfx::NativeWindow parent) {
  ClairBrowserWindow* found = nullptr;
  if (!parent) {
    return found;
  }
  NSWindow* top = parent.GetNativeNSWindow();
  while (top.parentWindow) {
    top = top.parentWindow;
  }
  ForEachCurrentBrowserWindowInterfaceOrderedByActivation(
      [&](BrowserWindowInterface* browser) {
        ClairBrowserWindow* window = ClairBrowserWindow::FromBrowser(browser);
        if (window && window->GetNativeWindow().GetNativeNSWindow() == top) {
          found = window;
          return false;
        }
        return true;
      });
  return found;
}

// Prompts the alert can't show: those that take typed input or a parent's
// approval, or have no accept button.
bool NeedsChromiumDialog(const extensions::InstallPromptData& prompt) {
  using Data = extensions::InstallPromptData;
  return prompt.type() == Data::EXTENSION_REQUEST_PROMPT ||
         prompt.type() == Data::EXTENSION_PENDING_REQUEST_PROMPT ||
         prompt.type() == Data::EXTENSION_PARENT_APPROVAL_PROMPT ||
         prompt.requires_parent_permission() ||
         prompt.GetAcceptButtonLabel().empty();
}

// One entry per permission, with its details on the following lines.
NSArray<NSString*>* PermissionLines(
    const extensions::InstallPromptPermissions& permissions) {
  NSMutableArray<NSString*>* lines = [NSMutableArray array];
  for (size_t i = 0; i < permissions.permissions.size(); ++i) {
    std::u16string line = permissions.permissions[i];
    if (i < permissions.details.size() && !permissions.details[i].empty()) {
      std::u16string details;
      base::ReplaceChars(permissions.details[i], u"\n", u"\n    ", &details);
      line += u"\n    " + details;
    }
    [lines addObject:base::SysUTF16ToNSString(line)];
  }
  return lines;
}

class PromptHandle : public clair::ExtensionPromptHandle {
 public:
  PromptHandle(base::WeakPtr<ClairExtensions> owner, int prompt_id)
      : owner_(std::move(owner)), prompt_id_(prompt_id) {}
  ~PromptHandle() override {
    if (owner_) {
      owner_->DismissPrompt(prompt_id_);
    }
  }

 private:
  base::WeakPtr<ClairExtensions> owner_;
  const int prompt_id_;
};

}  // namespace

namespace clair {

bool ShowExtensionInstallPrompt(
    ExtensionInstallPromptShowParams* show_params,
    extensions::ExtensionInstallPromptClient::DoneCallback& done_callback,
    std::unique_ptr<extensions::InstallPromptData>& prompt) {
  content::WebContents* contents = show_params->GetParentWebContents();
  ClairBrowserWindow* window =
      contents ? ClairBrowserWindow::FromWebContents(contents) : nullptr;
  if (!window) {
    window = WindowForNativeWindow(show_params->GetParentWindow());
  }
  if (!window || !window->extensions() || NeedsChromiumDialog(*prompt)) {
    return false;
  }
  ClairExtensions* owner = window->extensions();
  ClairChromiumExtensionPrompt* snapshot =
      [[ClairChromiumExtensionPrompt alloc] init];
  snapshot.promptID = owner->NewPromptID();
  const bool is_install =
      prompt->type() == extensions::InstallPromptData::INSTALL_PROMPT;
  snapshot.kind = is_install ? ClairExtensionPromptKindInstall
                             : ClairExtensionPromptKindOther;
  if (const extensions::Extension* extension = prompt->extension()) {
    snapshot.extensionName = base::SysUTF16ToNSString(
        extensions::ui_util::GetFixupExtensionNameForUIDisplay(extension->name()));
  }
  snapshot.icon = prompt->icon().IsEmpty() ? nil : prompt->icon().ToNSImage();
  snapshot.permissions = PermissionLines(prompt->GetPermissions());
  if (!is_install) {
    snapshot.title = base::SysUTF16ToNSString(prompt->GetDialogTitle());
    snapshot.permissionsHeading =
        base::SysUTF16ToNSString(prompt->GetPermissionsHeading());
    snapshot.acceptLabel = base::SysUTF16ToNSString(prompt->GetAcceptButtonLabel());
    snapshot.cancelLabel = base::SysUTF16ToNSString(prompt->GetAbortButtonLabel());
  }
  prompt->OnDialogOpened();
  owner->ShowPrompt(
      snapshot,
      base::BindOnce(
          [](extensions::ExtensionInstallPromptClient::DoneCallback done,
             std::unique_ptr<extensions::InstallPromptData> data,
             bool accepted) {
            using Payload =
                extensions::ExtensionInstallPromptClient::DoneCallbackPayload;
            using Result = extensions::ExtensionInstallPromptClient::Result;
            if (!accepted) {
              data->OnDialogCanceled();
              std::move(done).Run(Payload(Result::USER_CANCELED));
              return;
            }
            data->OnDialogAccepted();
            std::move(done).Run(Payload(
                data->ShouldWithheldPermissionsOnDialogAccept()
                    ? Result::ACCEPTED_WITH_WITHHELD_PERMISSIONS
                    : Result::ACCEPTED));
          },
          std::move(done_callback), std::move(prompt)));
  return true;
}

std::unique_ptr<ExtensionPromptHandle> ShowExtensionRemovePrompt(
    gfx::NativeWindow parent,
    const extensions::Extension* extension,
    const gfx::ImageSkia& icon,
    base::OnceCallback<void(bool accepted)> answered) {
  ClairBrowserWindow* window = WindowForNativeWindow(parent);
  if (!window || !window->extensions() || !extension) {
    return nullptr;
  }
  ClairExtensions* owner = window->extensions();
  ClairChromiumExtensionPrompt* snapshot =
      [[ClairChromiumExtensionPrompt alloc] init];
  snapshot.promptID = owner->NewPromptID();
  snapshot.kind = ClairExtensionPromptKindRemove;
  snapshot.extensionName = base::SysUTF16ToNSString(
      extensions::ui_util::GetFixupExtensionNameForUIDisplay(extension->name()));
  snapshot.icon = icon.isNull() ? nil : gfx::Image(icon).ToNSImage();
  owner->ShowPrompt(snapshot, std::move(answered));
  return std::make_unique<PromptHandle>(owner->AsWeakPtr(),
                                        static_cast<int>(snapshot.promptID));
}

bool ExtensionInstalled(BrowserWindowInterface* browser,
                        const extensions::Extension* extension) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromBrowser(browser);
  if (!window || !window->extensions()) {
    return false;
  }
  window->extensions()->PinNewExtension(*extension);
  return true;
}

}  // namespace clair
