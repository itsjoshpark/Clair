// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#ifndef CHROME_BROWSER_CLAIR_WINDOW_CLAIR_EXTENSIONS_H_
#define CHROME_BROWSER_CLAIR_WINDOW_CLAIR_EXTENSIONS_H_

#import <Foundation/Foundation.h>

#include <memory>
#include <string>

#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/scoped_observation.h"
#import "chrome/browser/clair/ClairHost.h"
#include "chrome/browser/extensions/extension_action_dispatcher.h"
#include "chrome/browser/ui/extensions/extensions_container.h"
#include "chrome/browser/ui/toolbar/toolbar_actions_model.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_registry_observer.h"
#include "ui/base/unowned_user_data/scoped_unowned_user_data.h"

class ClairBrowserWindow;

namespace extensions {
class ExtensionViewHost;
}  // namespace extensions

// The sidebar's extension actions (design D7): snapshots from Chromium's
// toolbar model and actions, running an action as the toolbar would, and its
// popup page, which ClairUI shows attached to the clicked button. It is the
// browser's ExtensionsContainer, so chrome.action.openPopup() reaches it.
class ClairExtensions : public ExtensionsContainer,
                        public ToolbarActionsModel::Observer,
                        public extensions::ExtensionActionDispatcher::Observer,
                        public extensions::ExtensionRegistryObserver {
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
  bool flush_posted_ = false;
  base::ScopedObservation<ToolbarActionsModel, ToolbarActionsModel::Observer>
      model_observation_{this};
  base::ScopedObservation<extensions::ExtensionActionDispatcher,
                          extensions::ExtensionActionDispatcher::Observer>
      dispatcher_observation_{this};
  base::ScopedObservation<extensions::ExtensionRegistry,
                          extensions::ExtensionRegistryObserver>
      registry_observation_{this};
  std::unique_ptr<ui::ScopedUnownedUserData<ExtensionsContainer>>
      scoped_user_data_;
  base::WeakPtrFactory<ClairExtensions> weak_factory_{this};
};

#endif  // CHROME_BROWSER_CLAIR_WINDOW_CLAIR_EXTENSIONS_H_
