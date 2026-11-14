// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#import "chrome/browser/clair/clair_space_tabs.h"

#include <algorithm>
#include <utility>

#include "base/barrier_closure.h"
#include "base/check.h"
#include "base/functional/bind.h"
#include "base/logging.h"
#include "base/no_destructor.h"
#include "base/strings/escape.h"
#include "base/strings/string_number_conversions.h"
#include "base/strings/sys_string_conversions.h"
#include "base/task/sequenced_task_runner.h"
#include "chrome/browser/browser_process.h"
#include "chrome/browser/clair/clair_profiles.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/clair/window/clair_window_group.h"
#include "chrome/browser/clair/window/clair_peeks.h"
#include "chrome/browser/clair/window/clair_space_session.h"
#include "chrome/browser/media/webrtc/media_capture_devices_dispatcher.h"
#include "chrome/browser/media/webrtc/media_stream_capture_indicator.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/profiles/profile_manager.h"
#include "chrome/browser/profiles/profiles_state.h"
#include "chrome/browser/sessions/session_service.h"
#include "chrome/browser/sessions/session_service_factory.h"
#include "chrome/browser/ssl/chrome_security_state_util.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/recently_audible_helper.h"
#include "chrome/browser/ui/tabs/tab_enums.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/common/webui_url_constants.h"
#include "components/content_settings/browser/page_specific_content_settings.h"
#include "components/content_settings/core/common/content_settings_types.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/infobars/content/content_infobar_manager.h"
#include "components/infobars/core/confirm_infobar_delegate.h"
#include "components/infobars/core/infobar.h"
#include "components/security_state/core/security_state.h"
#include "components/sessions/content/session_tab_helper.h"
#include "components/url_formatter/url_formatter.h"
#include "content/public/browser/navigation_controller.h"
#include "content/public/browser/web_contents.h"
#include "content/public/browser/web_contents_observer.h"
#include "content/public/common/referrer.h"
#include "content/public/common/url_constants.h"
#include "net/base/apple/url_conversions.h"
#include "ui/base/page_transition_types.h"
#include "ui/gfx/image/image.h"
#include "url/gurl.h"

namespace {

// --- The Space tag (D2, D6) ---------------------------------------------------

const void* const kSpaceTagKey = &kSpaceTagKey;
const void* const kSpaceTabsKey = &kSpaceTabsKey;
const void* const kPlaceholderKey = &kPlaceholderKey;

// share-tabs-across-windows D2: marks a window's placeholder tab.
struct PlaceholderMark : public base::SupportsUserData::Data {};

// A tab's Space, kept on its WebContents so it follows the tab between
// windows and comes back with it from a session.
struct SpaceTag : public base::SupportsUserData::Data {
  std::string space;
  // From a restored session: the tab's index in its Space's list when it was
  // saved. It orders restored tabs until the list is next written.
  std::optional<int> rank;
  // What the session holds for the tab, so it's written only on a change.
  std::string written_space;
  int written_rank = -1;
  // add-profiles D6: the window group a restored tab's window belonged to,
  // and the group the session holds for it.
  std::string window;
  std::string written_window;
};

// add-profiles D6: the group of the window holding `contents`, or empty.
std::string GroupOf(content::WebContents* contents) {
  ClairBrowserWindow* window = ClairBrowserWindow::FromWebContents(contents);
  ClairWindowGroup* group = window ? ClairWindowGroup::Of(window) : nullptr;
  return group ? group->id() : std::string();
}

SpaceTag* GetTag(content::WebContents* contents) {
  return contents ? static_cast<SpaceTag*>(contents->GetUserData(kSpaceTagKey))
                  : nullptr;
}

SpaceTag* EnsureTag(content::WebContents* contents) {
  if (SpaceTag* tag = GetTag(contents)) {
    return tag;
  }
  auto tag = std::make_unique<SpaceTag>();
  SpaceTag* raw = tag.get();
  contents->SetUserData(kSpaceTagKey, std::move(tag));
  return raw;
}

std::set<ClairSpaceTabs*>& Instances() {
  static base::NoDestructor<std::set<ClairSpaceTabs*>> instances;
  return *instances;
}

// --- Snapshots (moved from clair_browser_bridge.mm) --------------------------

NSString* NSStringOrNil(const std::u16string& text) {
  return text.empty() ? nil : base::SysUTF16ToNSString(text);
}

ClairTabIndicators IndicatorsOf(content::WebContents* contents) {
  ClairTabIndicators indicators = ClairTabIndicatorsNone;
  scoped_refptr<MediaStreamCaptureIndicator> capture =
      MediaCaptureDevicesDispatcher::GetInstance()
          ->GetMediaStreamCaptureIndicator();
  if (capture) {
    if (capture->IsCapturingVideo(contents)) {
      indicators |= ClairTabIndicatorsCamera;
    }
    if (capture->IsCapturingAudio(contents)) {
      indicators |= ClairTabIndicatorsMicrophone;
    }
    if (capture->IsBeingMirrored(contents) || capture->IsCapturingTab(contents) ||
        capture->IsCapturingWindow(contents) ||
        capture->IsCapturingDisplay(contents)) {
      indicators |= ClairTabIndicatorsScreenCapture;
    }
  }
  auto* settings = content_settings::PageSpecificContentSettings::GetForFrame(
      contents->GetPrimaryMainFrame());
  if (settings) {
    if (settings->IsContentAllowed(ContentSettingsType::GEOLOCATION)) {
      indicators |= ClairTabIndicatorsLocation;
    }
    for (ContentSettingsType type :
         {ContentSettingsType::GEOLOCATION, ContentSettingsType::NOTIFICATIONS,
          ContentSettingsType::MEDIASTREAM_CAMERA,
          ContentSettingsType::MEDIASTREAM_MIC}) {
      if (settings->IsContentBlocked(type)) {
        indicators |= ClairTabIndicatorsBlockedPermission;
      }
    }
  }
  return indicators;
}

}  // namespace

@interface ClairChromiumInfobar : NSObject <ClairInfobar>
- (instancetype)initWithInfobar:(infobars::InfoBar*)infobar
                       delegate:(ConfirmInfoBarDelegate*)delegate;
@end

@implementation ClairChromiumInfobar
@synthesize infobarID = _infobarID;
@synthesize message = _message;
@synthesize linkText = _linkText;
@synthesize okButtonLabel = _okButtonLabel;
@synthesize cancelButtonLabel = _cancelButtonLabel;
@synthesize icon = _icon;

- (instancetype)initWithInfobar:(infobars::InfoBar*)infobar
                       delegate:(ConfirmInfoBarDelegate*)delegate {
  if ((self = [super init])) {
    _infobarID = clair::InfobarIDOf(infobar);
    _message = base::SysUTF16ToNSString(delegate->GetMessageText());
    _linkText = NSStringOrNil(delegate->GetLinkText());
    const int buttons = delegate->GetButtons();
    if (buttons & ConfirmInfoBarDelegate::BUTTON_OK) {
      _okButtonLabel = base::SysUTF16ToNSString(
          delegate->GetButtonLabel(ConfirmInfoBarDelegate::BUTTON_OK));
    }
    if (buttons & ConfirmInfoBarDelegate::BUTTON_CANCEL) {
      _cancelButtonLabel = base::SysUTF16ToNSString(
          delegate->GetButtonLabel(ConfirmInfoBarDelegate::BUTTON_CANCEL));
    }
  }
  return self;
}
@end

@interface ClairChromiumTab : NSObject <ClairTab>
- (instancetype)initWithContents:(content::WebContents*)contents
                    peekParentID:(ClairTabID)peekParentID
                          peekID:(ClairTabID)peekID
                         spaceID:(NSString*)spaceID
                       browserID:(ClairBrowserID)browserID;
@end

@implementation ClairChromiumTab
@synthesize tabID = _tabID;
@synthesize title = _title;
@synthesize url = _url;
@synthesize urlText = _urlText;
@synthesize displayHost = _displayHost;
@synthesize isNewTabPage = _isNewTabPage;
@synthesize isNotSecure = _isNotSecure;
@synthesize favicon = _favicon;
@synthesize isLoading = _isLoading;
@synthesize loadProgress = _loadProgress;
@synthesize canGoBack = _canGoBack;
@synthesize canGoForward = _canGoForward;
@synthesize isAudible = _isAudible;
@synthesize isMuted = _isMuted;
@synthesize isCrashed = _isCrashed;
@synthesize indicators = _indicators;
@synthesize infobars = _infobars;
@synthesize peekParentID = _peekParentID;
@synthesize peekID = _peekID;
@synthesize spaceID = _spaceID;
@synthesize browserID = _browserID;

- (instancetype)initWithContents:(content::WebContents*)contents
                    peekParentID:(ClairTabID)peekParentID
                          peekID:(ClairTabID)peekID
                         spaceID:(NSString*)spaceID
                       browserID:(ClairBrowserID)browserID {
  if ((self = [super init])) {
    _peekParentID = peekParentID;
    _peekID = peekID;
    _spaceID = [spaceID copy];
    _browserID = browserID;
    const GURL& url = contents->GetVisibleURL();
    _tabID = clair::TabIDOf(contents);
    _url = url.is_valid() ? net::NSURLWithGURL(url) : nil;
    _urlText = base::SysUTF16ToNSString(url_formatter::FormatUrl(
        url, url_formatter::kFormatUrlOmitNothing, base::UnescapeRule::NORMAL,
        nullptr, nullptr, nullptr));
    _displayHost = url.has_host() ? base::SysUTF16ToNSString(
                                        url_formatter::IDNToUnicode(url.host()))
                                  : nil;
    _isNewTabPage = url.SchemeIs(content::kChromeUIScheme) &&
                    (url.host() == chrome::kChromeUINewTabHost ||
                     url.host() == chrome::kChromeUINewTabPageHost);
    const security_state::SecurityLevel security_level =
        chrome_security_state::GetSecurityLevel(contents);
    _isNotSecure = security_level == security_state::WARNING ||
                   security_level == security_state::DANGEROUS;
    std::u16string title = contents->GetTitle();
    _title = base::SysUTF16ToNSString(title.empty() ? url_formatter::FormatUrl(url)
                                                    : title);
    if (auto* favicons =
            favicon::ContentFaviconDriver::FromWebContents(contents);
        favicons && favicons->FaviconIsValid()) {
      gfx::Image image = favicons->GetFavicon();
      _favicon = image.IsEmpty() ? nil : image.ToNSImage();
    }
    // Chromium's toolbar and tab strip state (replace-browser-window D1): a
    // frame loading on its own or a same-document navigation doesn't show
    // stop.
    _isLoading = contents->IsLoading() && contents->ShouldShowLoadingUI();
    _loadProgress = contents->GetLoadProgress();
    _canGoBack = contents->GetController().CanGoBack();
    _canGoForward = contents->GetController().CanGoForward();
    auto* audible = RecentlyAudibleHelper::FromWebContents(contents);
    _isAudible = contents->IsCurrentlyAudible() ||
                 (audible && audible->WasRecentlyAudible());
    _isMuted = contents->IsAudioMuted();
    _isCrashed = contents->IsCrashed();
    _indicators = IndicatorsOf(contents);
    NSMutableArray<id<ClairInfobar>>* infobars = [NSMutableArray array];
    if (auto* manager =
            infobars::ContentInfoBarManager::FromWebContents(contents)) {
      for (infobars::InfoBar* infobar : manager->infobars()) {
        if (ConfirmInfoBarDelegate* delegate =
                infobar->delegate()->AsConfirmInfoBarDelegate()) {
          [infobars addObject:[[ClairChromiumInfobar alloc]
                                  initWithInfobar:infobar
                                         delegate:delegate]];
        }
      }
    }
    _infobars = [infobars copy];
  }
  return self;
}
@end

@interface ClairChromiumSpace : NSObject <ClairSpace>
- (instancetype)initWithSpace:(const clair::Space&)space;
@end

@implementation ClairChromiumSpace
@synthesize spaceID = _spaceID;
@synthesize name = _name;
@synthesize icon = _icon;
@synthesize profileID = _profileID;

- (instancetype)initWithSpace:(const clair::Space&)space {
  if ((self = [super init])) {
    _spaceID = base::SysUTF8ToNSString(space.id);
    _name = base::SysUTF8ToNSString(space.name);
    _icon = space.icon.empty() ? nil : base::SysUTF8ToNSString(space.icon);
    _profileID = base::SysUTF8ToNSString(space.profile);
  }
  return self;
}
@end

// --- Observation ---------------------------------------------------------------

// Tells the lists when a tab's load progress or security state changes, so it
// rides the tab's coalesced push (replace-browser-window D4).
class ClairSpaceTabs::ProgressObserver : public content::WebContentsObserver {
 public:
  ProgressObserver(ClairSpaceTabs* owner, content::WebContents* contents)
      : content::WebContentsObserver(contents), owner_(owner) {}

  // content::WebContentsObserver:
  void LoadProgressChanged(double progress) override {
    owner_->TabChanged(web_contents());
  }
  // Mixed content can be found after a load has finished.
  void DidChangeVisibleSecurityState() override {
    owner_->TabChanged(web_contents());
  }
  // D4: the page answered a close, before Chromium acts on the answer.
  void BeforeUnloadFired(bool proceed) override {
    if (ClairBrowserWindow* window =
            ClairBrowserWindow::FromWebContents(web_contents())) {
      window->BeforeUnloadFired(web_contents(), proceed);
    }
  }

 private:
  const raw_ptr<ClairSpaceTabs> owner_;
};

// --- ClairSpaceTabs ------------------------------------------------------------

// static
ClairSpaceTabs* ClairSpaceTabs::ForProfile(Profile* profile) {
  if (!profile) {
    return nullptr;
  }
  if (auto* existing =
          static_cast<ClairSpaceTabs*>(profile->GetUserData(kSpaceTabsKey))) {
    return existing;
  }
  auto owned = std::make_unique<ClairSpaceTabs>(profile);
  ClairSpaceTabs* raw = owned.get();
  profile->SetUserData(kSpaceTabsKey, std::move(owned));
  return raw;
}

// static
ClairSpaceTabs* ClairSpaceTabs::ForWebContents(content::WebContents* contents) {
  if (!contents) {
    return nullptr;
  }
  return static_cast<ClairSpaceTabs*>(
      contents->GetBrowserContext()->GetUserData(kSpaceTabsKey));
}

// static
std::vector<ClairSpaceTabs*> ClairSpaceTabs::All() {
  return std::vector<ClairSpaceTabs*>(Instances().begin(), Instances().end());
}

// static
void ClairSpaceTabs::FlushAll() {
  for (ClairSpaceTabs* tabs : All()) {
    tabs->Flush();
  }
}

// static
void ClairSpaceTabs::SetRestoredTag(content::WebContents* contents,
                                    const std::string& space,
                                    std::optional<int> rank) {
  if (!contents || space.empty()) {
    return;
  }
  SpaceTag* tag = EnsureTag(contents);
  tag->space = space;
  tag->rank = rank;
}

// static
void ClairSpaceTabs::SetRestoredWindowTag(content::WebContents* contents,
                                          const std::string& group) {
  if (contents && !group.empty()) {
    EnsureTag(contents)->window = group;
  }
}

// static
std::string ClairSpaceTabs::WindowTag(content::WebContents* contents) {
  SpaceTag* tag = GetTag(contents);
  return tag ? tag->window : std::string();
}

// static
std::map<std::string, std::string> ClairSpaceTabs::SessionTags(
    content::WebContents* contents) {
  std::map<std::string, std::string> tags;
  SpaceTag* tag = GetTag(contents);
  ClairSpaceTabs* lists = ForWebContents(contents);
  if (!tag || !lists || !lists->is_regular() || tag->space.empty()) {
    return tags;
  }
  int rank = tag->written_rank;
  tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  if (auto list = lists->lists_.find(tag->space);
      tab && list != lists->lists_.end()) {
    auto it = std::ranges::find(list->second, tab->GetHandle());
    if (it != list->second.end()) {
      rank = static_cast<int>(it - list->second.begin());
    }
  }
  tags[clair::kSpaceSessionKey] = tag->space;
  if (rank >= 0) {
    tags[clair::kOrderSessionKey] = base::NumberToString(rank);
  }
  if (std::string group = GroupOf(contents); !group.empty()) {
    tags[clair::kWindowSessionKey] = group;
  }
  return tags;
}

// static
void ClairSpaceTabs::MarkPlaceholder(content::WebContents* contents) {
  if (contents && !IsPlaceholder(contents)) {
    contents->SetUserData(kPlaceholderKey, std::make_unique<PlaceholderMark>());
  }
}

// static
bool ClairSpaceTabs::IsPlaceholder(content::WebContents* contents) {
  return contents && contents->GetUserData(kPlaceholderKey);
}

ClairSpaceTabs::ClairSpaceTabs(Profile* profile) : profile_(profile) {
  if (profile->IsOffTheRecord()) {
    static int next_private_space = 1;
    private_space_ =
        "private-" + base::NumberToString(next_private_space++);
  }
  Instances().insert(this);
}

ClairSpaceTabs::~ClairSpaceTabs() {
  Instances().erase(this);
  infobar_observations_.RemoveAllObservations();
  progress_observers_.clear();
  for (ClairBrowserWindow* window : windows_) {
    if (window->browser()) {
      window->browser()->tab_strip_model()->RemoveObserver(this);
    }
  }
}

void ClairSpaceTabs::AddBrowser(ClairBrowserWindow* window) {
  if (!window || std::ranges::find(windows_, window) != windows_.end()) {
    return;
  }
  windows_.push_back(window);
  TabStripModel* strip = window->browser()->tab_strip_model();
  strip->AddObserver(this);
  for (int i = 0; i < strip->count(); ++i) {
    Watch(strip->GetWebContentsAt(i));
    Insert(strip, strip->GetTabAtIndex(i), i);
  }
}

void ClairSpaceTabs::RemoveBrowser(ClairBrowserWindow* window) {
  auto it = std::ranges::find(windows_, window);
  if (it == windows_.end()) {
    return;
  }
  windows_.erase(it);
  TabStripModel* strip =
      window->browser() ? window->browser()->tab_strip_model() : nullptr;
  if (!strip) {
    return;
  }
  strip->RemoveObserver(this);
  for (int i = 0; i < strip->count(); ++i) {
    Unwatch(strip->GetWebContentsAt(i));
    Remove(strip->GetTabAtIndex(i));
  }
}

ClairBrowserWindow* ClairSpaceTabs::WindowFor(const TabStripModel* model) const {
  for (ClairBrowserWindow* window : windows_) {
    if (window->browser() && window->browser()->tab_strip_model() == model) {
      return window;
    }
  }
  return nullptr;
}

std::string ClairSpaceTabs::SpaceOf(const tabs::TabInterface* tab) const {
  if (!tab) {
    return std::string();
  }
  const tabs::TabHandle handle = tab->GetHandle();
  for (const auto& [space, list] : lists_) {
    if (std::ranges::find(list, handle) != list.end()) {
      return space;
    }
  }
  return std::string();
}

std::string ClairSpaceTabs::SpaceOf(content::WebContents* contents) const {
  return SpaceOf(contents ? tabs::TabInterface::MaybeGetFromContents(contents)
                          : nullptr);
}

std::string ClairSpaceTabs::IntendedSpaceOf(tabs::TabInterface* tab) const {
  std::string space = SpaceOf(tab);
  if (!space.empty() || !tab || !is_regular()) {
    return space;
  }
  SpaceTag* tag = GetTag(tab->GetContents());
  return tag && clair::ClairSpaceStore::Get()->Contains(tag->space)
             ? tag->space
             : std::string();
}

std::vector<tabs::TabInterface*> ClairSpaceTabs::TabsIn(
    const std::string& space) const {
  std::vector<tabs::TabInterface*> result;
  auto list = lists_.find(space);
  if (list == lists_.end()) {
    return result;
  }
  for (const tabs::TabHandle& handle : list->second) {
    if (tabs::TabInterface* tab = handle.Get()) {
      result.push_back(tab);
    }
  }
  return result;
}

std::vector<tabs::TabInterface*> ClairSpaceTabs::TabsIn(
    const std::string& space,
    const Browser* browser) const {
  std::vector<tabs::TabInterface*> result;
  for (tabs::TabInterface* tab : TabsIn(space)) {
    if (tab->GetBrowserWindowInterface() == browser) {
      result.push_back(tab);
    }
  }
  return result;
}

std::vector<std::string> ClairSpaceTabs::SpacesWithTabs() const {
  std::vector<std::string> spaces;
  for (const auto& [space, list] : lists_) {
    if (!list.empty()) {
      spaces.push_back(space);
    }
  }
  return spaces;
}

id<ClairTab> ClairSpaceTabs::Snapshot(content::WebContents* contents) const {
  ClairTabID peek_parent_id = ClairTabIDNone;
  ClairTabID peek_id = ClairTabIDNone;
  ClairBrowserID browser_id = 0;
  tabs::TabInterface* tab = tabs::TabInterface::MaybeGetFromContents(contents);
  if (ClairBrowserWindow* window = ClairBrowserWindow::FromWebContents(contents)) {
    browser_id = window->browser()->GetSessionID().id();
    if (ClairPeeks* peeks = window->peeks(); peeks && tab) {
      if (tabs::TabInterface* peek = peeks->ShownPeekOf(tab)) {
        peek_id = peek->GetHandle().raw_value();
      }
      if (std::optional<int32_t> parent = peeks->ParentIDOf(tab)) {
        peek_parent_id = *parent;
      }
    }
  }
  return [[ClairChromiumTab alloc]
      initWithContents:contents
          peekParentID:peek_parent_id
                peekID:peek_id
               spaceID:base::SysUTF8ToNSString(SpaceOf(tab))
             browserID:browser_id];
}

NSArray<id<ClairTab>>* ClairSpaceTabs::Snapshots(const std::string& space) const {
  NSMutableArray<id<ClairTab>>* snapshots = [NSMutableArray array];
  for (tabs::TabInterface* tab : TabsIn(space)) {
    [snapshots addObject:Snapshot(tab->GetContents())];
  }
  return snapshots;
}

// --- Placing tabs (D2) ---

void ClairSpaceTabs::Insert(TabStripModel* model,
                            tabs::TabInterface* tab,
                            int index) {
  if (!tab) {
    return;
  }
  content::WebContents* contents = tab->GetContents();
  Remove(tab);
  ClairBrowserWindow* window = WindowFor(model);
  // share-tabs-across-windows D2: a placeholder, marked before it joined the
  // strip, is in no Space.
  if (IsPlaceholder(contents)) {
    return;
  }
  clair::ClairSpaceStore* store = clair::ClairSpaceStore::Get();
  SpaceTag* tag = GetTag(contents);
  std::string space;
  std::optional<int> rank;
  if (!is_regular()) {
    space = private_space_;
  } else if (tag && store->Contains(tag->space)) {
    // Restored from a session, or moved from another window.
    space = tag->space;
    rank = tag->rank;
  } else {
    // A new tab joins the Space its window shows (D3). A Peek joins its
    // parent's once it's linked (PeekLinked).
    space = window && store->Contains(window->shown_space())
                ? window->shown_space()
                : store->last_space();
  }
  tag = EnsureTag(contents);
  tag->space = space;
  tag->rank = rank;

  std::vector<tabs::TabHandle>& list = lists_[space];
  size_t at = 0;
  if (rank) {
    // By its saved rank, after the tabs ranked the same: ties keep the
    // strip's order. Tabs listed since the restore count by their index.
    at = list.size();
    for (size_t i = 0; i < list.size(); ++i) {
      tabs::TabInterface* other = list[i].Get();
      SpaceTag* other_tag = other ? GetTag(other->GetContents()) : nullptr;
      const bool after = other_tag && other_tag->rank
                             ? *other_tag->rank > *rank
                             : static_cast<int>(i) >= *rank;
      if (after) {
        at = i;
        break;
      }
    }
  } else if (index > 0) {
    // Directly after the nearest tab before it in the strip that belongs to
    // the same Space, which keeps a Peek being expanded below its parent.
    // At index 0, where clair::NewTabIndex puts new tabs, it goes to the top.
    for (int i = std::min(index, model->count()) - 1; i >= 0; --i) {
      tabs::TabInterface* before = model->GetTabAtIndex(i);
      if (!before || before == tab) {
        continue;
      }
      auto it = std::ranges::find(list, before->GetHandle());
      if (it != list.end()) {
        at = static_cast<size_t>(it - list.begin()) + 1;
        break;
      }
    }
  }
  list.insert(list.begin() + at, tab->GetHandle());
  ListChanged(space);
}

std::string ClairSpaceTabs::Remove(const tabs::TabInterface* tab) {
  if (!tab) {
    return std::string();
  }
  const tabs::TabHandle handle = tab->GetHandle();
  for (auto& [space, list] : lists_) {
    if (std::erase(list, handle) > 0) {
      ListChanged(space);
      return space;
    }
  }
  return std::string();
}

std::vector<tabs::TabInterface*> ClairSpaceTabs::FamilyOf(
    tabs::TabInterface* tab) const {
  std::vector<tabs::TabInterface*> family{tab};
  ClairBrowserWindow* window =
      tab ? ClairBrowserWindow::FromWebContents(tab->GetContents()) : nullptr;
  if (window && window->peeks()) {
    if (tabs::TabInterface* peek = window->peeks()->PeekOf(tab)) {
      family.push_back(peek);
    }
  }
  return family;
}

std::vector<tabs::TabHandle> ClairSpaceTabs::TakeFamily(
    std::vector<tabs::TabHandle>& list,
    tabs::TabInterface* tab) const {
  std::vector<tabs::TabHandle> handles;
  for (tabs::TabInterface* member : FamilyOf(tab)) {
    handles.push_back(member->GetHandle());
  }
  std::erase_if(list, [&handles](const tabs::TabHandle& handle) {
    return std::ranges::find(handles, handle) != handles.end();
  });
  return handles;
}

void ClairSpaceTabs::MoveTab(tabs::TabInterface* tab, int index) {
  const std::string space = SpaceOf(tab);
  if (space.empty()) {
    return;
  }
  std::vector<tabs::TabHandle>& list = lists_[space];
  const std::vector<tabs::TabHandle> handles = TakeFamily(list, tab);
  const size_t at = static_cast<size_t>(
      std::clamp(index, 0, static_cast<int>(list.size())));
  list.insert(list.begin() + at, handles.begin(), handles.end());
  ListChanged(space);
}

void ClairSpaceTabs::MoveTabBeside(tabs::TabInterface* tab,
                                   tabs::TabInterface* anchor,
                                   bool after) {
  const std::string space = SpaceOf(tab);
  if (space.empty() || !anchor || anchor == tab || SpaceOf(anchor) != space) {
    return;
  }
  // The anchor's Peek directly follows it, so after the anchor is after its
  // Peek.
  const tabs::TabHandle beside =
      (after ? FamilyOf(anchor).back() : anchor)->GetHandle();
  std::vector<tabs::TabHandle>& list = lists_[space];
  const std::vector<tabs::TabHandle> handles = TakeFamily(list, tab);
  auto it = std::ranges::find(list, beside);
  if (it != list.end() && after) {
    ++it;
  }
  list.insert(it, handles.begin(), handles.end());
  ListChanged(space);
}

void ClairSpaceTabs::SetSpace(tabs::TabInterface* tab,
                              const std::string& space) {
  if (!tab || !is_regular() ||
      !clair::ClairSpaceStore::Get()->Contains(space) || SpaceOf(tab) == space) {
    return;
  }
  std::vector<tabs::TabHandle> handles;
  for (tabs::TabInterface* member : FamilyOf(tab)) {
    Remove(member);
    SpaceTag* tag = EnsureTag(member->GetContents());
    tag->space = space;
    tag->rank.reset();
    handles.push_back(member->GetHandle());
  }
  std::vector<tabs::TabHandle>& list = lists_[space];
  list.insert(list.begin(), handles.begin(), handles.end());
  ListChanged(space);
}

void ClairSpaceTabs::PeekLinked(tabs::TabInterface* parent,
                                tabs::TabInterface* peek) {
  const std::string space = SpaceOf(parent);
  if (space.empty() || !peek) {
    return;
  }
  Remove(peek);
  EnsureTag(peek->GetContents())->space = space;
  std::vector<tabs::TabHandle>& list = lists_[space];
  auto it = std::ranges::find(list, parent->GetHandle());
  list.insert(it == list.end() ? list.end() : it + 1, peek->GetHandle());
  ListChanged(space);
}

void ClairSpaceTabs::SpaceRemoved(const std::string& space,
                                  const std::string& fallback) {
  auto found = lists_.find(space);
  if (found == lists_.end()) {
    return;
  }
  std::vector<tabs::TabHandle> left = std::move(found->second);
  lists_.erase(found);
  changed_spaces_.erase(space);
  std::vector<tabs::TabHandle> moved;
  for (const tabs::TabHandle& handle : left) {
    if (tabs::TabInterface* tab = handle.Get()) {
      EnsureTag(tab->GetContents())->space = fallback;
      moved.push_back(handle);
    }
  }
  if (moved.empty()) {
    return;
  }
  std::vector<tabs::TabHandle>& list = lists_[fallback];
  list.insert(list.begin(), moved.begin(), moved.end());
  ListChanged(fallback);
}

// --- Moving between windows (share-tabs-across-windows D1, D2) ---

void ClairSpaceTabs::BeginMove(tabs::TabInterface* tab) {
  if (tab) {
    moving_.insert(tab->GetHandle());
  }
}

void ClairSpaceTabs::EndMove(tabs::TabInterface* tab) {
  if (!tab) {
    return;
  }
  moving_.erase(tab->GetHandle());
  // Its `browserID` changed, and the session holds it under another window.
  if (SpaceTag* tag = GetTag(tab->GetContents())) {
    tag->written_space.clear();
    tag->written_rank = -1;
    tag->written_window.clear();
  }
  ListChanged(SpaceOf(tab));
}

void ClairSpaceTabs::ListPlaceholder(TabStripModel* model,
                                     tabs::TabInterface* tab) {
  if (!tab) {
    return;
  }
  tab->GetContents()->RemoveUserData(kPlaceholderKey);
  // Index 0 puts it at the top of the shown Space's list.
  Insert(model, tab, 0);
}

// --- Pushes (D9) ---

void ClairSpaceTabs::ListChanged(const std::string& space) {
  if (space.empty()) {
    return;
  }
  changed_spaces_.insert(space);
  PostFlush();
}

void ClairSpaceTabs::AllListsChanged() {
  for (const auto& [space, list] : lists_) {
    for (const tabs::TabHandle& handle : list) {
      if (tabs::TabInterface* tab = handle.Get()) {
        if (SpaceTag* tag = GetTag(tab->GetContents())) {
          tag->written_window.clear();
        }
      }
    }
    ListChanged(space);
  }
}

void ClairSpaceTabs::TabChanged(content::WebContents* contents) {
  const ClairTabID tab_id = clair::TabIDOf(contents);
  if (tab_id == ClairTabIDNone) {
    return;
  }
  changed_tabs_.insert(static_cast<int32_t>(tab_id));
  PostFlush();
}

void ClairSpaceTabs::PostFlush() {
  if (flush_posted_) {
    return;
  }
  flush_posted_ = true;
  base::SequencedTaskRunner::GetCurrentDefault()->PostTask(
      FROM_HERE,
      base::BindOnce(&ClairSpaceTabs::Flush, weak_factory_.GetWeakPtr()));
}

void ClairSpaceTabs::Flush() {
  flush_posted_ = false;
  std::set<std::string> spaces = std::move(changed_spaces_);
  changed_spaces_.clear();
  std::set<int32_t> changed = std::move(changed_tabs_);
  changed_tabs_.clear();
  for (const std::string& space : spaces) {
    // Handles of tabs that went without a removal, as at shutdown.
    if (auto list = lists_.find(space); list != lists_.end()) {
      std::erase_if(list->second, [](const tabs::TabHandle& handle) {
        return !handle.Get();
      });
    }
    if (is_regular()) {
      WriteSessionTags(space);
    }
    clair::NotifyTabsInSpace(space);
  }
  for (int32_t raw : changed) {
    tabs::TabInterface* tab = tabs::TabHandle(raw).Get();
    if (tab && !SpaceOf(tab).empty()) {
      clair::NotifyTab(Snapshot(tab->GetContents()));
    }
  }
}

// --- Sessions (D6) ---

void ClairSpaceTabs::WriteSessionTags(const std::string& space) {
  auto list = lists_.find(space);
  if (list == lists_.end()) {
    return;
  }
  SessionService* service =
      SessionServiceFactory::GetForProfileIfExisting(profile_);
  int index = 0;
  for (const tabs::TabHandle& handle : list->second) {
    tabs::TabInterface* tab = handle.Get();
    if (!tab) {
      continue;
    }
    content::WebContents* contents = tab->GetContents();
    SpaceTag* tag = EnsureTag(contents);
    // Restored ranks have done their work once the list is written.
    tag->rank.reset();
    BrowserWindowInterface* browser = tab->GetBrowserWindowInterface();
    const std::string group = GroupOf(contents);
    if (service && browser &&
        (tag->written_space != space || tag->written_rank != index ||
         tag->written_window != group)) {
      const SessionID window_id = browser->GetSessionID();
      const SessionID tab_id = sessions::SessionTabHelper::IdForTab(contents);
      if (window_id.is_valid() && tab_id.is_valid()) {
        service->AddTabExtraData(window_id, tab_id, clair::kSpaceSessionKey,
                                 space);
        service->AddTabExtraData(window_id, tab_id, clair::kOrderSessionKey,
                                 base::NumberToString(index));
        if (!group.empty()) {
          service->AddTabExtraData(window_id, tab_id, clair::kWindowSessionKey,
                                   group);
        }
        tag->written_space = space;
        tag->written_rank = index;
        tag->written_window = group;
      }
    }
    ++index;
  }
}

// --- TabStripModelObserver ---

void ClairSpaceTabs::OnTabStripModelChanged(
    TabStripModel* model,
    const TabStripModelChange& change,
    const TabStripSelectionChange& selection) {
  switch (change.type()) {
    case TabStripModelChange::kInserted:
      for (const auto& inserted : change.GetInsert()->contents) {
        Watch(inserted.contents);
        // share-tabs-across-windows D1: a tab Clair moves keeps its place.
        if (inserted.tab && moving_.contains(inserted.tab->GetHandle())) {
          continue;
        }
        Insert(model, inserted.tab, inserted.index);
      }
      break;
    case TabStripModelChange::kRemoved:
      // A tab moving to another window comes back with its tag (D2).
      for (const auto& removed : change.GetRemove()->contents) {
        if (removed.tab && moving_.contains(removed.tab->GetHandle())) {
          continue;
        }
        Unwatch(removed.contents);
        Remove(removed.tab);
        // share-tabs-across-windows D2: a window showing a still of the tab
        // shows its placeholder as a new tab page.
        if (removed.remove_reason == TabRemovedReason::kDeleted &&
            removed.tab) {
          const tabs::TabHandle handle = removed.tab->GetHandle();
          for (ClairBrowserWindow* window : windows_) {
            if (window->still_tab() == handle) {
              window->StillTabClosed();
            }
          }
        }
      }
      break;
    case TabStripModelChange::kReplaced: {
      const TabStripModelChange::Replace* replace = change.GetReplace();
      Unwatch(replace->old_contents);
      Watch(replace->new_contents);
      // The tab keeps its handle; its Space moves to the new contents.
      if (SpaceTag* old_tag = GetTag(replace->old_contents)) {
        SpaceTag* new_tag = EnsureTag(replace->new_contents);
        new_tag->space = old_tag->space;
        new_tag->rank = old_tag->rank;
      }
      ListChanged(SpaceOf(replace->tab));
      break;
    }
    case TabStripModelChange::kMoved:
    case TabStripModelChange::kSelectionOnly:
      // The strip's order means nothing to the user (D2).
      break;
  }
}

void ClairSpaceTabs::OnTabChangedAt(tabs::TabInterface* tab,
                                    TabChangeType change_type) {
  TabChanged(tab->GetContents());
}

void ClairSpaceTabs::OnTabStripModelDestroyed(TabStripModel* model) {
  std::erase_if(windows_, [model](ClairBrowserWindow* window) {
    return !window->browser() || window->browser()->tab_strip_model() == model;
  });
}

// --- Infobars and progress ---

void ClairSpaceTabs::Watch(content::WebContents* contents) {
  if (!contents) {
    return;
  }
  auto* manager = infobars::ContentInfoBarManager::FromWebContents(contents);
  if (manager && !infobar_observations_.IsObservingSource(manager)) {
    infobar_observations_.AddObservation(manager);
  }
  if (std::ranges::none_of(progress_observers_, [contents](const auto& observer) {
        return observer->web_contents() == contents;
      })) {
    progress_observers_.push_back(
        std::make_unique<ProgressObserver>(this, contents));
  }
}

void ClairSpaceTabs::Unwatch(content::WebContents* contents) {
  if (!contents) {
    return;
  }
  auto* manager = infobars::ContentInfoBarManager::FromWebContents(contents);
  if (manager && infobar_observations_.IsObservingSource(manager)) {
    infobar_observations_.RemoveObservation(manager);
  }
  std::erase_if(progress_observers_, [contents](const auto& observer) {
    return observer->web_contents() == contents;
  });
}

void ClairSpaceTabs::InfobarChanged(infobars::InfoBar* infobar) {
  if (content::WebContents* contents =
          infobars::ContentInfoBarManager::WebContentsFromInfoBar(infobar)) {
    TabChanged(contents);
  }
}

void ClairSpaceTabs::OnInfoBarAdded(infobars::InfoBar* infobar) {
  if (!infobar->delegate()->AsConfirmInfoBarDelegate()) {
    // replace-browser-window D8: only confirm infobars have a native bar.
    // Others are logged and dismissed once the manager has finished adding
    // this one.
    LOG(WARNING) << "Clair: dismissing an infobar the native window can't "
                    "show (identifier "
                 << static_cast<int>(infobar->delegate()->GetIdentifier())
                 << ")";
    // Its tab may close, taking the infobar and its manager, before then.
    base::WeakPtr<infobars::InfoBar> weak_infobar = infobar->AsWeakPtr();
    dispatch_async(dispatch_get_main_queue(), ^{
      if (weak_infobar && weak_infobar->owner()) {
        weak_infobar->RemoveSelf();
      }
    });
    return;
  }
  InfobarChanged(infobar);
}

void ClairSpaceTabs::OnInfoBarRemoved(infobars::InfoBar* infobar,
                                      bool animate) {
  InfobarChanged(infobar);
}

void ClairSpaceTabs::OnInfoBarReplaced(infobars::InfoBar* old_infobar,
                                       infobars::InfoBar* new_infobar) {
  InfobarChanged(new_infobar);
}

void ClairSpaceTabs::OnManagerWillBeDestroyed(
    infobars::InfoBarManager* manager) {
  if (infobar_observations_.IsObservingSource(manager)) {
    infobar_observations_.RemoveObservation(manager);
  }
}

// --- The host's Space calls (D7, D9) ----------------------------------------

namespace clair {

namespace {

NSHashTable<id<ClairSpacesObserver>>* Observers() {
  static NSHashTable<id<ClairSpacesObserver>>* observers =
      [NSHashTable weakObjectsHashTable];
  return observers;
}

// Tells the observers when the store changes.
class StoreWatcher : public ClairSpaceStore::Observer {
 public:
  StoreWatcher() { ClairSpaceStore::Get()->AddObserver(this); }

  // ClairSpaceStore::Observer:
  void OnSpacesChanged() override {
    KeepLastUsedProfileOnASpace();
    NSArray<id<ClairSpace>>* spaces = SpaceSnapshots();
    for (id<ClairSpacesObserver> observer in Observers().allObjects) {
      [observer spacesDidChange:spaces];
    }
  }
};

}  // namespace

ClairTabID TabIDOf(content::WebContents* contents) {
  tabs::TabInterface* tab =
      contents ? tabs::TabInterface::MaybeGetFromContents(contents) : nullptr;
  return tab ? tab->GetHandle().raw_value() : ClairTabIDNone;
}

NSInteger InfobarIDOf(const infobars::InfoBar* infobar) {
  return reinterpret_cast<NSInteger>(infobar);
}

void AddSpacesObserver(id<ClairSpacesObserver> observer) {
  static base::NoDestructor<StoreWatcher> watcher;
  ClairProfiles::Get()->Start();
  [Observers() addObject:observer];
}

void NotifyProfiles(NSArray<id<ClairProfile>>* profiles) {
  for (id<ClairSpacesObserver> observer in Observers().allObjects) {
    [observer profilesDidChange:profiles];
  }
}

void KeepLastUsedProfileOnASpace() {
  ProfileManager* manager = g_browser_process->profile_manager();
  if (!manager) {
    return;
  }
  ClairSpaceStore* store = ClairSpaceStore::Get();
  const std::string last_used =
      manager->GetLastUsedProfileDir().BaseName().AsUTF8Unsafe();
  if (store->SpaceCountOf(last_used) > 0) {
    return;
  }
  const std::string profile = store->ProfileOf(store->last_space());
  if (!profile.empty()) {
    profiles::SetLastUsedProfile(base::FilePath::FromUTF8Unsafe(profile));
  }
}

NSArray<id<ClairSpace>>* SpaceSnapshots() {
  NSMutableArray<id<ClairSpace>>* spaces = [NSMutableArray array];
  for (const Space& space : ClairSpaceStore::Get()->spaces()) {
    [spaces addObject:[[ClairChromiumSpace alloc] initWithSpace:space]];
  }
  return spaces;
}

NSArray<id<ClairTab>>* TabsInSpace(const std::string& space) {
  NSMutableArray<id<ClairTab>>* tabs = [NSMutableArray array];
  for (ClairSpaceTabs* lists : ClairSpaceTabs::All()) {
    [tabs addObjectsFromArray:lists->Snapshots(space)];
  }
  return tabs;
}

void NotifyTabsInSpace(const std::string& space) {
  if (Observers().count == 0) {
    return;
  }
  NSArray<id<ClairTab>>* tabs = TabsInSpace(space);
  NSString* space_id = base::SysUTF8ToNSString(space);
  for (id<ClairSpacesObserver> observer in Observers().allObjects) {
    [observer tabsDidChange:tabs inSpace:space_id];
  }
}

void NotifyTab(id<ClairTab> tab) {
  for (id<ClairSpacesObserver> observer in Observers().allObjects) {
    [observer tabDidChange:tab];
  }
}

namespace {

// Closes the tabs of a deleted Space in every window, each with its
// leave-page confirmation, and removes it (D7).
void CloseTabsOfDeletedSpace(const std::string& space,
                             const std::string& neighbour) {
  ClairSpaceStore* store = ClairSpaceStore::Get();
  if (!store->Contains(space)) {
    return;
  }
  for (ClairSpaceTabs* lists : ClairSpaceTabs::All()) {
    if (!lists->is_regular()) {
      continue;
    }
    std::vector<tabs::TabHandle> handles;
    for (tabs::TabInterface* tab : lists->TabsIn(space)) {
      handles.push_back(tab->GetHandle());
    }
    for (const tabs::TabHandle& handle : handles) {
      tabs::TabInterface* tab = handle.Get();
      ClairBrowserWindow* window =
          tab ? ClairBrowserWindow::FromWebContents(tab->GetContents())
              : nullptr;
      TabStripModel* strip =
          window ? window->browser()->tab_strip_model() : nullptr;
      const int strip_index =
          strip ? strip->GetIndexOfTab(tab) : TabStripModel::kNoTab;
      if (strip_index != TabStripModel::kNoTab) {
        strip->CloseWebContentsAt(
            strip_index, TabCloseTypes::CLOSE_USER_GESTURE |
                             TabCloseTypes::CLOSE_CREATE_HISTORICAL_TAB);
      }
    }
  }
  if (store->last_space() == space) {
    store->SetLastSpace(neighbour);
  }
  if (store->Remove(space)) {
    for (ClairSpaceTabs* lists : ClairSpaceTabs::All()) {
      lists->SpaceRemoved(space, neighbour);
    }
  }
}

// add-profiles D9: opens `url` as a tab of `space`, at `rank` in its list, in
// `window`'s strip, without activating it.
tabs::TabInterface* OpenTabInSpace(ClairBrowserWindow* window,
                                   const GURL& url,
                                   const std::string& space,
                                   int rank) {
  Profile* profile = window->browser()->GetProfile();
  std::unique_ptr<content::WebContents> contents =
      content::WebContents::Create(content::WebContents::CreateParams(profile));
  // Its Space and place, before it joins the strip, as a restored tab's.
  ClairSpaceTabs::SetRestoredTag(contents.get(), space, rank);
  contents->GetController().LoadURL(
      url.is_valid() ? url : GURL(chrome::kChromeUINewTabURL),
      content::Referrer(), ui::PAGE_TRANSITION_AUTO_TOPLEVEL, std::string());
  content::WebContents* raw = contents.get();
  TabStripModel* strip = window->browser()->tab_strip_model();
  strip->InsertWebContentsAt(strip->count(), std::move(contents),
                             AddTabTypes::ADD_NONE);
  return tabs::TabInterface::MaybeGetFromContents(raw);
}

// add-profiles D9: closes `row` and its Peek at once, without their pages
// asking before leaving. A window with a still of it shows a new tab page
// (share-tabs-across-windows D2).
void CloseReopened(tabs::TabHandle handle) {
  tabs::TabInterface* row = handle.Get();
  ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(row);
  if (!row || !holder) {
    return;
  }
  for (ClairBrowserWindow* window : ClairBrowserWindow::All()) {
    window->DropPendingTakeOf(row);
  }
  TabStripModel* strip = holder->browser()->tab_strip_model();
  std::vector<tabs::TabHandle> family;
  if (holder->peeks()) {
    if (tabs::TabInterface* peek = holder->peeks()->PeekOf(row)) {
      family.push_back(peek->GetHandle());
    }
  }
  family.push_back(handle);
  for (const tabs::TabHandle& member : family) {
    tabs::TabInterface* tab = member.Get();
    const int index = tab ? strip->GetIndexOfTab(tab) : TabStripModel::kNoTab;
    if (index != TabStripModel::kNoTab) {
      strip->DetachAndDeleteWebContentsAt(index);
    }
  }
}

// add-profiles D9: reopens each of `rows`, in order, as a tab of `space` in
// its window group's member for the Space's profile, from `first_rank` on,
// and closes the originals. In a window that showed one of them, the tab
// reopened from it becomes active, and the group shows its member.
void ReopenInProfile(std::vector<tabs::TabHandle> rows,
                     const std::string& space,
                     int first_rank) {
  ClairSpaceStore* store = ClairSpaceStore::Get();
  const std::string profile = store->ProfileOf(space);
  ClairProfiles::Get()->Load(
      profile,
      base::BindOnce(
          [](std::vector<tabs::TabHandle> rows, std::string space,
             int first_rank, Profile* loaded) {
            if (!loaded || !ClairSpaceStore::Get()->Contains(space)) {
              return;
            }
            const std::string profile = ClairProfiles::IDOf(loaded);
            int rank = first_rank;
            for (const tabs::TabHandle& handle : rows) {
              tabs::TabInterface* row = handle.Get();
              ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(row);
              ClairWindowGroup* group =
                  holder ? ClairWindowGroup::Of(holder) : nullptr;
              if (!row || !group) {
                continue;
              }
              const bool shown =
                  holder->IsActiveRow(row) && !holder->IsHiddenMember();
              const std::string previous = group->shown_space();
              const GURL url = row->GetContents()->GetVisibleURL();
              const int this_rank = rank++;
              // The profile is loaded, so the member comes at once.
              group->EnsureMember(
                  profile,
                  base::BindOnce(
                      [](tabs::TabHandle handle, GURL url, std::string space,
                         int rank, bool shown, std::string previous,
                         base::WeakPtr<ClairBrowserWindow> holder,
                         ClairBrowserWindow* member) {
                        if (!member) {
                          return;
                        }
                        tabs::TabInterface* reopened =
                            OpenTabInSpace(member, url, space, rank);
                        if (shown && reopened) {
                          ClairWindowGroup* group =
                              ClairWindowGroup::Of(member);
                          if (group && group->shown() != member) {
                            member->BeginSwapIn(previous);
                          }
                          member->ActivateTab(reopened);
                          if (group) {
                            group->SwapTo(member, previous);
                          }
                        }
                        CloseReopened(handle);
                      },
                      handle, url, space, this_rank, shown, previous,
                      holder->GetWeakPtr()));
            }
          },
          std::move(rows), space, first_rank));
}

}  // namespace

void DeleteSpace(const std::string& space) {
  ClairSpaceStore* store = ClairSpaceStore::Get();
  std::optional<size_t> index = store->IndexOf(space);
  if (!index || store->spaces().size() <= 1) {
    return;
  }
  // The Space before it, or the one after when it was first.
  const std::string neighbour =
      store->spaces()[*index > 0 ? *index - 1 : 1].id;
  // Each window showing it shows the neighbour first, which may be of another
  // profile, whose member may need its profile loaded (add-profiles D3).
  std::vector<ClairWindowGroup*> showing;
  for (ClairWindowGroup* group : ClairWindowGroup::RegularByActivation()) {
    if (group->shown_space() == space) {
      showing.push_back(group);
    }
  }
  base::RepeatingClosure barrier = base::BarrierClosure(
      showing.size(),
      base::BindOnce(&CloseTabsOfDeletedSpace, space, neighbour));
  if (showing.empty()) {
    return;
  }
  for (ClairWindowGroup* group : showing) {
    group->ShowSpace(neighbour,
                     base::BindOnce(
                         [](base::RepeatingClosure barrier, ClairBrowserWindow*) {
                           barrier.Run();
                         },
                         barrier));
  }
}

void MoveTabToSpace(tabs::TabInterface* tab, const std::string& space) {
  ClairSpaceTabs* lists =
      tab ? ClairSpaceTabs::ForWebContents(tab->GetContents()) : nullptr;
  ClairSpaceStore* store = ClairSpaceStore::Get();
  if (!lists || !lists->is_regular() || !store->Contains(space)) {
    return;
  }
  ClairBrowserWindow* window =
      ClairBrowserWindow::FromWebContents(tab->GetContents());
  // A Peek moves with its parent.
  if (window && window->peeks()) {
    if (tabs::TabInterface* parent = window->peeks()->ParentOf(tab)) {
      tab = parent;
    }
  }
  if (lists->SpaceOf(tab) == space) {
    return;
  }
  // add-profiles D9: a page can't change profile; it reopens at the top of
  // the other Space, in its profile.
  if (store->ProfileOf(space) != ClairProfiles::IDOf(lists->profile())) {
    ReopenInProfile({tab->GetHandle()}, space, /*first_rank=*/0);
    return;
  }
  // Another window with a still of it picks its next tab, as if the tab had
  // closed there.
  for (ClairBrowserWindow* other : ClairBrowserWindow::All()) {
    if (other != window && other->still_tab() == tab->GetHandle()) {
      other->StillTabClosed();
    }
  }
  const bool follows = window && window->IsActiveRow(tab);
  lists->SetSpace(tab, space);
  // The window follows its active tab, which stays active (D9, replacing
  // add-spaces D7's next-tab choice).
  if (follows) {
    window->FollowActiveTab();
  }
}

void SetSpaceProfile(const std::string& space, const std::string& profile) {
  ClairSpaceStore* store = ClairSpaceStore::Get();
  const std::string old_profile = store->ProfileOf(space);
  if (old_profile.empty() || old_profile == profile ||
      !store->SetProfile(space, profile)) {
    return;
  }
  // D9: every tab of the Space, in its order, Peeks left out.
  std::vector<tabs::TabHandle> rows;
  for (ClairSpaceTabs* lists : ClairSpaceTabs::All()) {
    if (!lists->is_regular() ||
        ClairProfiles::IDOf(lists->profile()) != old_profile) {
      continue;
    }
    for (tabs::TabInterface* tab : lists->TabsIn(space)) {
      ClairBrowserWindow* holder = ClairBrowserWindow::HolderOf(tab);
      if (holder && holder->peeks() && holder->peeks()->ParentOf(tab)) {
        continue;
      }
      rows.push_back(tab->GetHandle());
    }
  }
  if (rows.empty()) {
    return;
  }
  ReopenInProfile(std::move(rows), space, /*first_rank=*/0);
}

}  // namespace clair
