// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#include "chrome/browser/clair/window/clair_peeks.h"

#include <algorithm>
#include <string>
#include <utility>

#include "base/auto_reset.h"
#include "base/functional/bind.h"
#include "base/scoped_observation.h"
#include "base/task/single_thread_task_runner.h"
#include "chrome/app/chrome_command_ids.h"
#import "chrome/browser/clair/ClairHost.h"
#import "chrome/browser/clair/window/clair_browser_bridge.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/clair/window/clair_peek_session.h"
#import "chrome/browser/clair/clair_space_tabs.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_commands.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "components/input/native_web_keyboard_event.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/navigation_handle.h"
#include "content/public/browser/page_navigator.h"
#include "content/public/browser/page.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_widget_host.h"
#include "content/public/browser/render_widget_host_observer.h"
#include "content/public/browser/visibility.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/common/referrer.h"
#include "third_party/blink/public/common/input/web_input_event.h"
#include "third_party/blink/public/common/input/web_keyboard_event.h"
#include "third_party/blink/public/mojom/input/input_event_result.mojom-shared.h"
#include "ui/base/page_transition_types.h"
#include "ui/events/keycodes/keyboard_codes.h"
#include "url/gurl.h"

namespace {

// A plain Esc press, as the page gets it before characters.
bool IsEscapeDown(const blink::WebKeyboardEvent& event) {
  return event.GetType() == blink::WebInputEvent::Type::kRawKeyDown &&
         event.windows_key_code == ui::VKEY_ESCAPE &&
         !(event.GetModifiers() & blink::WebInputEvent::kKeyModifiers);
}

}  // namespace

// Watches the Peek's main-frame widget for an Esc the page used, by
// preventing its default action or because a text field took it (D6).
class ClairPeeks::EscapeWatcher
    : public content::WebContentsObserver,
      public content::RenderWidgetHost::InputEventObserver,
      public content::RenderWidgetHostObserver {
 public:
  EscapeWatcher(ClairPeeks* owner, content::WebContents* contents)
      : content::WebContentsObserver(contents), owner_(owner) {
    Watch(contents->GetPrimaryMainFrame()->GetRenderWidgetHost());
  }

  ~EscapeWatcher() override { Unwatch(); }

  // content::WebContentsObserver:
  void PrimaryPageChanged(content::Page& page) override {
    Watch(page.GetMainDocument().GetRenderWidgetHost());
  }

  // content::RenderWidgetHost::InputEventObserver:
  void OnInputEventAck(const content::RenderWidgetHost& widget,
                       blink::mojom::InputEventResultSource source,
                       blink::mojom::InputEventResultState state,
                       const blink::WebInputEvent& event) override {
    if (state != blink::mojom::InputEventResultState::kConsumed ||
        !blink::WebInputEvent::IsKeyboardEventType(event.GetType()) ||
        !IsEscapeDown(static_cast<const blink::WebKeyboardEvent&>(event))) {
      return;
    }
    if (content::WebContents* contents = web_contents()) {
      owner_->EscapeKept(contents);
    }
  }

  // content::RenderWidgetHostObserver:
  void RenderWidgetHostDestroyed(content::RenderWidgetHost* widget) override {
    if (widget == widget_) {
      Unwatch();
    }
  }

 private:
  void Watch(content::RenderWidgetHost* widget) {
    if (widget == widget_) {
      return;
    }
    Unwatch();
    if (!widget) {
      return;
    }
    widget_ = widget;
    widget_->AddInputEventObserver(this);
    widget_observation_.Observe(widget_);
  }

  void Unwatch() {
    if (!widget_) {
      return;
    }
    widget_->RemoveInputEventObserver(this);
    widget_observation_.Reset();
    widget_ = nullptr;
  }

  const raw_ptr<ClairPeeks> owner_;
  raw_ptr<content::RenderWidgetHost> widget_ = nullptr;
  base::ScopedObservation<content::RenderWidgetHost,
                          content::RenderWidgetHostObserver>
      widget_observation_{this};
};

ClairPeeks::Pair::Pair(tabs::TabHandle parent, tabs::TabHandle peek)
    : parent(parent), peek(peek) {}
ClairPeeks::Pair::Pair(Pair&&) = default;
ClairPeeks::Pair& ClairPeeks::Pair::operator=(Pair&&) = default;
ClairPeeks::Pair::~Pair() = default;

ClairPeeks::ClairPeeks(ClairBrowserWindow* window)
    : window_(window), model_(window->browser()->tab_strip_model()) {
  model_->AddObserver(this);
}

ClairPeeks::~ClairPeeks() {
  pairs_.clear();
  if (model_) {
    model_->RemoveObserver(this);
  }
}

// --- The table ---

std::vector<ClairPeeks::Pair>::iterator ClairPeeks::FindByParent(
    const tabs::TabInterface* parent) {
  return std::ranges::find_if(pairs_, [parent](const Pair& pair) {
    return parent && pair.parent == parent->GetHandle();
  });
}

std::vector<ClairPeeks::Pair>::iterator ClairPeeks::FindByPeek(
    const tabs::TabInterface* peek) {
  return std::ranges::find_if(pairs_, [peek](const Pair& pair) {
    return peek && pair.peek == peek->GetHandle();
  });
}

std::vector<ClairPeeks::Pair>::const_iterator ClairPeeks::FindByParent(
    const tabs::TabInterface* parent) const {
  return std::ranges::find_if(pairs_, [parent](const Pair& pair) {
    return parent && pair.parent == parent->GetHandle();
  });
}

std::vector<ClairPeeks::Pair>::const_iterator ClairPeeks::FindByPeek(
    const tabs::TabInterface* peek) const {
  return std::ranges::find_if(pairs_, [peek](const Pair& pair) {
    return peek && pair.peek == peek->GetHandle();
  });
}

tabs::TabInterface* ClairPeeks::PeekOf(const tabs::TabInterface* parent) const {
  auto it = FindByParent(parent);
  return it == pairs_.end() ? nullptr : it->peek.Get();
}

tabs::TabInterface* ClairPeeks::ShownPeekOf(
    const tabs::TabInterface* parent) const {
  auto it = FindByParent(parent);
  return it == pairs_.end() || it->closing ? nullptr : it->peek.Get();
}

tabs::TabInterface* ClairPeeks::ParentOf(const tabs::TabInterface* peek) const {
  auto it = FindByPeek(peek);
  return it == pairs_.end() ? nullptr : it->parent.Get();
}

std::optional<int32_t> ClairPeeks::ParentIDOf(
    const tabs::TabInterface* peek) const {
  auto it = FindByPeek(peek);
  return it == pairs_.end() ? std::nullopt
                            : std::optional<int32_t>(it->parent.raw_value());
}

content::WebContents* ClairPeeks::PeekOf(content::WebContents* parent) const {
  tabs::TabInterface* peek =
      parent ? PeekOf(tabs::TabInterface::MaybeGetFromContents(parent))
             : nullptr;
  return peek ? peek->GetContents() : nullptr;
}

content::WebContents* ClairPeeks::ParentOf(content::WebContents* peek) const {
  tabs::TabInterface* parent =
      peek ? ParentOf(tabs::TabInterface::MaybeGetFromContents(peek)) : nullptr;
  return parent ? parent->GetContents() : nullptr;
}

std::set<content::WebContents*> ClairPeeks::PagesShownWith(
    content::WebContents* active) const {
  std::set<content::WebContents*> pages;
  if (!active) {
    return pages;
  }
  pages.insert(active);
  tabs::TabInterface* active_tab = tabs::TabInterface::MaybeGetFromContents(active);
  if (tabs::TabInterface* peek = active_tab ? ShownPeekOf(active_tab) : nullptr) {
    pages.insert(peek->GetContents());
  }
  if (content::WebContents* parent = ParentOf(active)) {
    pages.insert(parent);
  }
  return pages;
}

void ClairPeeks::Link(tabs::TabInterface* parent, tabs::TabInterface* peek) {
  if (!parent || !peek || parent == peek) {
    return;
  }
  // A tab has at most one Peek, and a Peek has no Peek of its own. Navigate
  // may also have put the tab somewhere else, as in another window or an
  // existing tab: only a tab right after its parent in this window is linked.
  const int parent_index =
      model_ ? strip()->GetIndexOfTab(parent) : TabStripModel::kNoTab;
  const int peek_index =
      model_ ? strip()->GetIndexOfTab(peek) : TabStripModel::kNoTab;
  if (parent_index == TabStripModel::kNoTab ||
      peek_index != parent_index + 1 || FindByParent(parent) != pairs_.end() ||
      FindByPeek(parent) != pairs_.end() || FindByPeek(peek) != pairs_.end()) {
    ActivateTab(peek);
    return;
  }
  pairs_.emplace_back(parent->GetHandle(), peek->GetHandle());
  pairs_.back().escape_watcher =
      std::make_unique<EscapeWatcher>(this, peek->GetContents());
  // D9: session restore and Reopen Closed Window leave it out.
  clair::TagPeekInSession(window_->browser(), peek->GetContents(), true);
  // It joins its parent's Space, right after it (add-spaces D2).
  if (ClairSpaceTabs* lists = window_->space_tabs()) {
    lists->PeekLinked(parent, peek);
  }
  Changed();
  ScheduleRepair();
  ActivateTab(peek);
}

void ClairPeeks::Unlink(std::vector<Pair>::iterator pair) {
  if (pair == pairs_.end()) {
    return;
  }
  if (confirm_peek_ == pair->peek) {
    confirm_peek_.reset();
  }
  pairs_.erase(pair);
  Changed();
}

void ClairPeeks::BeginClosing(std::vector<Pair>::iterator pair) {
  if (pair == pairs_.end() || pair->closing) {
    return;
  }
  pair->closing = true;
  // ClairUI hears it before the parent becomes active, so the card closes the
  // Peek at once (D4).
  Changed();
}

void ClairPeeks::RequestClose(tabs::TabInterface* peek, uint32_t close_types) {
  if (!model_ || !peek) {
    return;
  }
  auto pair = FindByPeek(peek);
  if (pair != pairs_.end()) {
    if (pair->close_requested) {
      return;
    }
    pair->close_requested = true;
  }
  const int index = strip()->GetIndexOfTab(peek);
  if (index != TabStripModel::kNoTab) {
    strip()->CloseWebContentsAt(index, close_types);
  }
}

void ClairPeeks::Untag(tabs::TabHandle peek) {
  if (tabs::TabInterface* tab = peek.Get()) {
    clair::TagPeekInSession(window_->browser(), tab->GetContents(), false);
  }
}

void ClairPeeks::Changed() {
  [window_->bridge() tabListChanged];
}

// --- Opening (D2) ---

content::WebContents* ClairPeeks::OpenURL(
    content::WebContents* source,
    const content::OpenURLParams& params,
    base::OnceCallback<void(content::NavigationHandle&)>&
        navigation_handle_callback) {
  tabs::TabInterface* source_tab =
      tabs::TabInterface::MaybeGetFromContents(source);
  NavigateParams nav_params(window_->browser(), params.url, params.transition);
  nav_params.FillNavigateParamsFromOpenURLParams(params);
  nav_params.source_contents = source;

  if (ParentOf(source_tab)) {
    // From a Peek: a new active tab at the top of the list.
    nav_params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
    nav_params.tabstrip_add_types = AddTabTypes::ADD_NONE;
    nav_params.window_action = NavigateParams::WindowAction::kShowWindow;
    base::WeakPtr<content::NavigationHandle> handle = Navigate(&nav_params);
    if (navigation_handle_callback && handle) {
      std::move(navigation_handle_callback).Run(*handle);
    }
    return nav_params.navigated_or_inserted_contents;
  }

  if (tabs::TabInterface* peek = PeekOf(source_tab)) {
    // The tab already has a Peek: it shows the link instead.
    content::NavigationController::LoadURLParams load_params(params);
    base::WeakPtr<content::NavigationHandle> handle =
        peek->GetContents()->GetController().LoadURLWithParams(load_params);
    if (navigation_handle_callback && handle) {
      std::move(navigation_handle_callback).Run(*handle);
    }
    ActivateTab(peek);
    return peek->GetContents();
  }

  // A new Peek, inserted in the background right after its parent and linked
  // before it becomes active, so ClairUI never sees it as a tab of its own.
  nav_params.disposition = WindowOpenDisposition::NEW_BACKGROUND_TAB;
  nav_params.tabstrip_index = strip()->GetIndexOfTab(source_tab) + 1;
  nav_params.tabstrip_add_types =
      AddTabTypes::ADD_FORCE_INDEX | AddTabTypes::ADD_INHERIT_OPENER;
  nav_params.window_action = NavigateParams::WindowAction::kNoAction;
  base::WeakPtr<content::NavigationHandle> handle = Navigate(&nav_params);
  if (navigation_handle_callback && handle) {
    std::move(navigation_handle_callback).Run(*handle);
  }
  content::WebContents* contents = nav_params.navigated_or_inserted_contents;
  if (contents) {
    Link(source_tab, tabs::TabInterface::MaybeGetFromContents(contents));
  }
  return contents;
}

content::WebContents* ClairPeeks::AddContents(
    content::WebContents* source,
    std::unique_ptr<content::WebContents> new_contents,
    const GURL& target_url,
    bool user_gesture) {
  tabs::TabInterface* source_tab =
      tabs::TabInterface::MaybeGetFromContents(source);

  if (tabs::TabInterface* peek = PeekOf(source_tab)) {
    // The tab already has a Peek: it shows the link, and the new contents
    // go.
    if (target_url.is_valid()) {
      peek->GetContents()->GetController().LoadURL(
          target_url, content::Referrer(), ui::PAGE_TRANSITION_LINK,
          std::string());
    }
    ActivateTab(peek);
    return nullptr;
  }

  const bool from_peek = ParentOf(source_tab) != nullptr;
  NavigateParams nav_params(window_->browser(), std::move(new_contents));
  nav_params.source_contents = source;
  nav_params.url = target_url;
  // Already past the popup blocker, as chrome::AddWebContents says.
  nav_params.user_gesture = true;
  nav_params.original_user_gesture = user_gesture;
  if (from_peek) {
    nav_params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
    nav_params.window_action = NavigateParams::WindowAction::kShowWindow;
    Navigate(&nav_params);
    return nav_params.navigated_or_inserted_contents;
  }
  nav_params.disposition = WindowOpenDisposition::NEW_BACKGROUND_TAB;
  nav_params.tabstrip_index = strip()->GetIndexOfTab(source_tab) + 1;
  nav_params.tabstrip_add_types =
      AddTabTypes::ADD_FORCE_INDEX | AddTabTypes::ADD_INHERIT_OPENER;
  nav_params.window_action = NavigateParams::WindowAction::kNoAction;
  Navigate(&nav_params);
  content::WebContents* contents = nav_params.navigated_or_inserted_contents;
  if (contents) {
    Link(source_tab, tabs::TabInterface::MaybeGetFromContents(contents));
  }
  return contents;
}

// --- Closing and expanding ---

void ClairPeeks::Close(tabs::TabInterface* tab) {
  auto pair = FindByParent(tab);
  if (pair == pairs_.end()) {
    pair = FindByPeek(tab);
  }
  if (pair == pairs_.end() || !model_) {
    return;
  }
  tabs::TabInterface* parent = pair->parent.Get();
  tabs::TabInterface* peek = pair->peek.Get();
  if (!peek) {
    Unlink(pair);
    return;
  }
  BeginClosing(pair);
  // D4: the parent comes back, rather than whichever tab Chromium would pick.
  if (parent && strip()->GetActiveTab() == peek) {
    ActivateTab(parent);
  }
  RequestClose(peek, TabCloseTypes::CLOSE_USER_GESTURE);
}

void ClairPeeks::CloseSoon(tabs::TabInterface* peek) {
  if (!peek) {
    return;
  }
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(
                     [](base::WeakPtr<ClairPeeks> peeks, tabs::TabHandle handle) {
                       if (peeks) {
                         peeks->Close(handle.Get());
                       }
                     },
                     weak_factory_.GetWeakPtr(), peek->GetHandle()));
}

void ClairPeeks::Expand(tabs::TabInterface* tab) {
  auto pair = FindByParent(tab);
  if (pair == pairs_.end()) {
    pair = FindByPeek(tab);
  }
  if (pair == pairs_.end() || !model_) {
    return;
  }
  tabs::TabInterface* parent = pair->parent.Get();
  tabs::TabInterface* peek = pair->peek.Get();
  // The Peek already sits right after its parent (D8).
  Unlink(pair);
  if (!peek) {
    return;
  }
  Untag(peek->GetHandle());
  if (strip()->GetActiveTab() != peek) {
    ActivateTab(peek);
  } else if (parent) {
    // The parent is no longer shown behind it.
    parent->GetContents()->UpdateWebContentsVisibility(
        content::Visibility::HIDDEN);
  }
}

// --- Moving between windows (share-tabs-across-windows D1) ---

tabs::TabInterface* ClairPeeks::Release(tabs::TabInterface* parent) {
  auto pair = FindByParent(parent);
  if (pair == pairs_.end()) {
    return nullptr;
  }
  tabs::TabInterface* peek = pair->closing ? nullptr : pair->peek.Get();
  if (!peek) {
    // A closing Peek stays to close here, as when its parent leaves.
    return nullptr;
  }
  // Out of the table before the strip hears of the move, so the move neither
  // orphans the Peek nor unlinks it as a tab that left on its own.
  if (confirm_peek_ == pair->peek) {
    confirm_peek_.reset();
  }
  pairs_.erase(pair);
  return peek;
}

void ClairPeeks::Adopt(tabs::TabInterface* parent, tabs::TabInterface* peek) {
  if (!model_ || !parent || !peek || parent == peek ||
      FindByParent(parent) != pairs_.end() || FindByPeek(peek) != pairs_.end()) {
    return;
  }
  pairs_.emplace_back(parent->GetHandle(), peek->GetHandle());
  pairs_.back().escape_watcher =
      std::make_unique<EscapeWatcher>(this, peek->GetContents());
  // D9: the session leaves it out under its new window too.
  clair::TagPeekInSession(window_->browser(), peek->GetContents(), true);
  Changed();
  ScheduleRepair();
}

// --- Tab commands (D7, D8) ---

void ClairPeeks::MoveQuietly(int from, int to) {
  if (from == TabStripModel::kNoTab || from == to) {
    return;
  }
  base::AutoReset<bool> moving(&moving_, true);
  strip()->MoveWebContentsAt(from, to, /*select_after_move=*/false);
}

void ClairPeeks::MoveTab(tabs::TabInterface* tab, int to_index) {
  if (!model_ || !tab) {
    return;
  }
  const int from = strip()->GetIndexOfTab(tab);
  if (from == TabStripModel::kNoTab) {
    return;
  }
  tabs::TabInterface* peek = PeekOf(tab);
  if (!peek) {
    strip()->MoveWebContentsAt(from, to_index, /*select_after_move=*/false);
    return;
  }
  // The pair moves as one: the tab ends at `to_index`, its Peek right after.
  const int to = std::clamp(to_index, 0, strip()->count() - 2);
  if (to > from) {
    MoveQuietly(strip()->GetIndexOfTab(peek), to + 1);
    MoveQuietly(strip()->GetIndexOfTab(tab), to);
  } else {
    MoveQuietly(from, to);
    MoveQuietly(strip()->GetIndexOfTab(peek), to + 1);
  }
}

void ClairPeeks::CloseTab(tabs::TabInterface* tab) {
  const int index = model_ && tab ? strip()->GetIndexOfTab(tab)
                                  : TabStripModel::kNoTab;
  if (index != TabStripModel::kNoTab) {
    strip()->CloseWebContentsAt(
        index, TabCloseTypes::CLOSE_USER_GESTURE |
                   TabCloseTypes::CLOSE_CREATE_HISTORICAL_TAB);
  }
}

tabs::TabInterface* ClairPeeks::LastOfFamily(tabs::TabInterface* tab) const {
  tabs::TabInterface* peek = PeekOf(tab);
  return peek ? peek : tab;
}

void ClairPeeks::ActivateTab(tabs::TabInterface* tab) {
  const int index =
      model_ && tab ? strip()->GetIndexOfTab(tab) : TabStripModel::kNoTab;
  if (index != TabStripModel::kNoTab) {
    strip()->ActivateTabAt(
        index, TabStripUserGestureDetails(
                   TabStripUserGestureDetails::GestureType::kOther));
  }
}

tabs::TabInterface* ClairPeeks::ActivePeek() const {
  tabs::TabInterface* active = model_ ? strip()->GetActiveTab() : nullptr;
  return active && FindByPeek(active) != pairs_.end() ? active : nullptr;
}

bool ClairPeeks::ExecuteCommand(int command) {
  if (!model_ || pairs_.empty()) {
    return false;
  }
  // The tab commands over the rows are the window's, which knows the
  // Space's order (add-spaces D5).
  tabs::TabInterface* peek = ActivePeek();
  tabs::TabInterface* parent = peek ? ParentOf(peek) : nullptr;
  if (!peek) {
    return false;
  }
  switch (command) {
    case IDC_CLOSE_TAB:
      // Cmd+W closes the Peek and shows its parent.
      Close(peek);
      return true;
    case IDC_OPEN_FILE:
      // Cmd+O expands the Peek, as in Arc, instead of File > Open File.
      Expand(peek);
      return true;
    case IDC_DUPLICATE_TAB: {
      const int index = parent ? strip()->GetIndexOfTab(parent)
                               : TabStripModel::kNoTab;
      if (index != TabStripModel::kNoTab &&
          chrome::CanDuplicateTabAt(window_->browser(), index)) {
        chrome::DuplicateTabAt(window_->browser(), index);
      }
      return true;
    }
    case IDC_MOVE_TAB_TO_NEW_WINDOW:
      // The parent moves without its Peek: Chromium moves the active tab,
      // which this makes the parent. The Peek, left behind without it, closes
      // once, with its leave-page confirmation (Repair).
      BeginClosing(FindByPeek(peek));
      ActivateTab(parent);
      return false;
    default:
      return false;
  }
}

// --- Esc (D6) ---

bool ClairPeeks::IsConfirmArmed(const tabs::TabInterface* peek) const {
  return peek && confirm_peek_ == peek->GetHandle() &&
         base::TimeTicks::Now() < confirm_until_;
}

content::KeyboardEventProcessingResult ClairPeeks::PreHandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  tabs::TabInterface* peek = ActivePeek();
  if (!IsEscapeDown(event) || !IsConfirmArmed(peek)) {
    return content::KeyboardEventProcessingResult::NOT_HANDLED;
  }
  // The second Esc closes the Peek before the page sees it, once the Peek's
  // WebContents has finished with the key.
  confirm_peek_.reset();
  CloseSoon(peek);
  return content::KeyboardEventProcessingResult::HANDLED;
}

bool ClairPeeks::HandleKeyboardEvent(
    const input::NativeWebKeyboardEvent& event) {
  tabs::TabInterface* peek = ActivePeek();
  if (!peek || !IsEscapeDown(event)) {
    return false;
  }
  // A focused text field keeps the Esc, as in Arc, even when it doesn't use
  // it.
  if (peek->GetContents()->IsFocusedElementEditable()) {
    EscapeKept(peek->GetContents());
    return true;
  }
  CloseSoon(peek);
  return true;
}

void ClairPeeks::EscapeKept(content::WebContents* contents) {
  tabs::TabInterface* peek = ActivePeek();
  if (!peek || peek->GetContents() != contents) {
    return;
  }
  confirm_peek_ = peek->GetHandle();
  confirm_until_ = base::TimeTicks::Now() + kConfirmDuration;
  [window_->clair_window() peekDidKeepEscape:kConfirmDuration.InSecondsF()];
}

// --- Keeping the pair together (D8) ---

void ClairPeeks::OnTabStripModelChanged(
    TabStripModel* model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  if (pairs_.empty()) {
    return;
  }
  switch (change.type()) {
    case TabStripModelChange::kInserted:
      ScheduleRepair();
      break;
    case TabStripModelChange::kRemoved:
      for (const auto& removed : change.GetRemove()->contents) {
        if (auto pair = FindByPeek(removed.tab); pair != pairs_.end()) {
          // A Peek that closed while it showed hands back to its parent.
          if (removed.contents == selection.old_contents &&
              removed.remove_reason == TabRemovedReason::kDeleted) {
            parents_to_activate_.push_back(pair->parent);
          }
          // One that left for another window leaves its parent unseen.
          if (removed.remove_reason != TabRemovedReason::kDeleted) {
            parents_to_hide_.push_back(pair->parent);
            Untag(pair->peek);
          }
          Unlink(pair);
        } else if (auto parent = FindByParent(removed.tab);
                   parent != pairs_.end()) {
          // Its Peek goes with it, once the tab strip is done.
          orphans_.push_back(parent->peek);
          parent->parent = tabs::TabHandle::Null();
        }
      }
      ScheduleRepair();
      break;
    case TabStripModelChange::kMoved: {
      const TabStripModelChange::Move* move = change.GetMove();
      if (moving_) {
        break;
      }
      if (auto pair = FindByPeek(move->tab); pair != pairs_.end()) {
        // Moved on its own, as by an extension: a normal tab from now on, and
        // its parent is no longer shown behind it.
        parents_to_hide_.push_back(pair->parent);
        Untag(pair->peek);
        Unlink(pair);
        ScheduleRepair();
      } else {
        ScheduleRepair();
      }
      break;
    }
    case TabStripModelChange::kReplaced: {
      const TabStripModelChange::Replace* replace = change.GetReplace();
      if (auto pair = FindByPeek(replace->tab); pair != pairs_.end()) {
        pair->escape_watcher =
            std::make_unique<EscapeWatcher>(this, replace->new_contents);
      }
      break;
    }
    case TabStripModelChange::kSelectionOnly:
      break;
  }
  if (selection.active_tab_changed()) {
    ActiveTabChanged(selection.new_tab);
  }
}

void ClairPeeks::ActiveTabChanged(tabs::TabInterface* active) {
  if (!active) {
    return;
  }
  if (auto pair = FindByPeek(active); pair != pairs_.end()) {
    // Shown again, as after its leave-page confirmation was declined.
    if (pair->closing) {
      pair->closing = false;
      pair->close_requested = false;
      Changed();
    }
    return;
  }
  // D4: a parent made active some other way than its Peek closing, as when
  // the tab next to it closes, shows its Peek. ClairUI already shows both;
  // the Peek becomes active once the tab strip is done.
  auto pair = FindByParent(active);
  if (pair == pairs_.end() || pair->closing || !pair->peek.Get()) {
    return;
  }
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE, base::BindOnce(&ClairPeeks::ShowPeekOf,
                                weak_factory_.GetWeakPtr(), pair->parent));
}

void ClairPeeks::ShowPeekOf(tabs::TabHandle parent_handle) {
  tabs::TabInterface* parent = parent_handle.Get();
  auto pair = FindByParent(parent);
  if (!model_ || pair == pairs_.end() || pair->closing ||
      strip()->GetActiveTab() != parent) {
    return;
  }
  ActivateTab(pair->peek.Get());
}

void ClairPeeks::OnTabStripModelDestroyed(TabStripModel* model) {
  pairs_.clear();
  model_ = nullptr;
}

void ClairPeeks::ScheduleRepair() {
  if (repair_posted_) {
    return;
  }
  repair_posted_ = true;
  // Not from inside the tab strip's notification, which can't be re-entered.
  base::SingleThreadTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&ClairPeeks::Repair, weak_factory_.GetWeakPtr()));
}

void ClairPeeks::Repair() {
  repair_posted_ = false;
  if (!model_) {
    return;
  }
  // Peeks whose parent closed or left the window.
  std::vector<tabs::TabHandle> orphans = std::move(orphans_);
  orphans_.clear();
  for (tabs::TabHandle handle : orphans) {
    RequestClose(handle.Get(), TabCloseTypes::CLOSE_USER_GESTURE);
    // Still there, waiting on its leave-page confirmation: a normal tab.
    if (handle.Get() &&
        strip()->GetIndexOfTab(handle.Get()) != TabStripModel::kNoTab) {
      Untag(handle);
    }
    Unlink(std::ranges::find_if(
        pairs_, [handle](const Pair& pair) { return pair.peek == handle; }));
  }
  // Each Peek right after its parent.
  std::vector<std::pair<tabs::TabHandle, tabs::TabHandle>> pairs;
  for (const Pair& pair : pairs_) {
    pairs.emplace_back(pair.parent, pair.peek);
  }
  for (const auto& [parent_handle, peek_handle] : pairs) {
    tabs::TabInterface* parent = parent_handle.Get();
    tabs::TabInterface* peek = peek_handle.Get();
    if (!parent || !peek) {
      continue;
    }
    const int parent_index = strip()->GetIndexOfTab(parent);
    const int peek_index = strip()->GetIndexOfTab(peek);
    if (parent_index == TabStripModel::kNoTab ||
        peek_index == TabStripModel::kNoTab || peek_index == parent_index + 1) {
      continue;
    }
    MoveQuietly(peek_index,
                peek_index < parent_index ? parent_index : parent_index + 1);
  }
  // Parents whose Peek left on their own, unless shown.
  std::vector<tabs::TabHandle> to_hide = std::move(parents_to_hide_);
  parents_to_hide_.clear();
  const std::set<content::WebContents*> shown =
      PagesShownWith(strip()->GetActiveWebContents());
  for (tabs::TabHandle handle : to_hide) {
    tabs::TabInterface* parent = handle.Get();
    if (parent && !shown.contains(parent->GetContents())) {
      parent->GetContents()->UpdateWebContentsVisibility(
          content::Visibility::HIDDEN);
    }
  }
  // The parent of a Peek that closed while it showed.
  std::vector<tabs::TabHandle> parents = std::move(parents_to_activate_);
  parents_to_activate_.clear();
  for (tabs::TabHandle handle : parents) {
    tabs::TabInterface* parent = handle.Get();
    if (parent && strip()->GetActiveTab() != parent) {
      ActivateTab(parent);
    }
  }
}
