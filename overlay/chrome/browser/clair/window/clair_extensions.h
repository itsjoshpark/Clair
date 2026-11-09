// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_EXTENSIONS_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_EXTENSIONS_H_

#import <Foundation/Foundation.h>

#include <map>
#include <memory>
#include <set>
#include <string>

#include "base/functional/callback.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_multi_source_observation.h"
#include "base/scoped_observation.h"
#import "chrome/browser/clair/ClairHost.h"
#include "chrome/browser/extensions/extension_action_dispatcher.h"
#include "chrome/browser/ui/extensions/extensions_container.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "extensions/browser/extension_icon_image.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"

class ClairBrowserWindow;

namespace extensions {
class Extension;
class ExtensionViewHost;
}  // namespace extensions

// The sidebar's extension actions (design D7): snapshots from Chromium's
// toolbar model and actions, running an action as the toolbar would, and its
// popup page, which ClairUI shows in a window beside the clicked button. It is
// the browser's ExtensionsContainer, so chrome.action.openPopup() reaches it.
// It also holds this window's install and remove confirmations
// (arc-extension-experience D4) and pins newly installed extensions (D5).
class ClairExtensions : public ExtensionsContainer,
                        public ToolbarActionsModel::Observer,
                        public extensions::ExtensionActionDispatcher::Observer,
                        public extensions::ExtensionRegistryObserver,
                        public extensions::IconImage::Observer {
 public:
  explicit ClairExtensions(ClairBrowserWindow* window);
  ClairExtensions(const ClairExtensions&) = delete;
  ClairExtensions& operator=(const ClairExtensions&) = delete;
  ~ClairExtensions() override;

  // The actions for the active tab, pinned first in the user's order.
  NSArray<id<ClairExtensionAction>>* Snapshot();

  // Runs an action from the sidebar; its popup attaches to `anchor`.
  void Run(const std::string& extension_id, ClairAnchorKind anchor);
  void SetPinned(const std::string& extension_id, bool pinned);
  // ClairUI's popover closed.
  void PopupClosedByUser();
  // The active tab changed, which changes icons and badges.
  void ActiveTabChanged();

  // Asks ClairUI to confirm `prompt`, whose ID came from NewPromptID().
  // `answer` runs once: with the user's answer, or false if the window closes.
  // It doesn't run if the prompt is dismissed.
  void ShowPrompt(id<ClairExtensionPrompt> prompt,
                  base::OnceCallback<void(bool accepted)> answer);
  int NewPromptID() { return next_prompt_id_++; }
  // An ID that's already answered or dismissed does nothing.
  void AnswerPrompt(int prompt_id, bool accepted);
  void DismissPrompt(int prompt_id);
  base::WeakPtr<ClairExtensions> AsWeakPtr() {
    return weak_factory_.GetWeakPtr();
  }

  // The user installed `extension` through a confirmation: pins its action,
  // now or as soon as the toolbar model has it.
  void PinNewExtension(const extensions::Extension& extension);

  // ExtensionsContainer:
  ToolbarActionViewModel* GetActionForId(const std::string& action_id) override;
  void HideActivePopup() override;
  void CloseExtensionsMenuIfOpen() override;
  bool ShowToolbarActionPopupForAPICall(const std::string& action_id,
                                        ShowPopupCallback callback) override;
  void ToggleExtensionsMenu() override;
  bool HasAnyExtensions() const override;

  // ToolbarActionsModel::Observer:
  void OnToolbarActionAdded(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarActionRemoved(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarActionUpdated(const ToolbarActionsModel::ActionId& id) override;
  void OnToolbarModelInitialized() override;
  void OnToolbarPinnedActionsChanged() override;
  void OnToolbarActionsModelShutdown() override;

  // extensions::ExtensionActionDispatcher::Observer:
  void OnExtensionActionUpdated(
      extensions::ExtensionAction* extension_action,
      content::WebContents* web_contents,
      content::BrowserContext* browser_context) override;
  void OnShuttingDown() override;

  // extensions::ExtensionRegistryObserver:
  void OnExtensionLoaded(content::BrowserContext* browser_context,
                         const extensions::Extension* extension) override;
  void OnExtensionUnloaded(content::BrowserContext* browser_context,
                           const extensions::Extension* extension,
                           extensions::UnloadedExtensionReason reason) override;

  // extensions::IconImage::Observer:
  void OnExtensionIconImageChanged(extensions::IconImage* image) override;
  void OnExtensionIconImageDestroyed(extensions::IconImage* image) override;

  class Popup;

 private:
  // Opens the popup page of `extension_id` at `anchor`. False when it has
  // none.
  bool OpenPopup(const std::string& extension_id,
                 ClairAnchorKind anchor,
                 ShowPopupCallback callback);
  void ClosePopup();
  void Changed();
  void Flush();

  const raw_ptr<ClairBrowserWindow> window_;
  std::unique_ptr<Popup> popup_;
  std::map<int, base::OnceCallback<void(bool)>> prompts_;
  int next_prompt_id_ = 1;
  std::set<std::string> pending_pins_;
  bool flush_posted_ = false;
  base::ScopedObservation<ToolbarActionsModel, ToolbarActionsModel::Observer>
      model_observation_{this};
  base::ScopedObservation<extensions::ExtensionActionDispatcher,
                          extensions::ExtensionActionDispatcher::Observer>
      dispatcher_observation_{this};
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      registry_observation_{this};
  // Default icons load from disk after the first snapshot asks for them.
  base::ScopedMultiSourceObservation<extensions::IconImage,
                                     extensions::IconImage::Observer>
      icon_observations_{this};
  std::unique_ptr<ui::ScopedUnownedUserData<ExtensionsContainer>>
      scoped_user_data_;
  base::WeakPtrFactory<ClairExtensions> weak_factory_{this};
};

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_EXTENSIONS_H_
