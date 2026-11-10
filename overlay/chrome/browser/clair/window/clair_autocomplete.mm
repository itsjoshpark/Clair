// Copyright 2026 The Clair Authors
// Use of this source code is governed by the GNU General Public License,
// version 3, found in the LICENSE file at the root of Clair's repository.

#import "chrome/browser/clair/window/clair_autocomplete.h"

#include <algorithm>
#include <memory>
#include <optional>
#include <vector>

#include "base/functional/bind.h"
#include "base/memory/raw_ptr.h"
#include "base/memory/weak_ptr.h"
#include "base/strings/strcat.h"
#include "base/strings/sys_string_conversions.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_provider_client.h"
#include "chrome/browser/autocomplete/chrome_autocomplete_scheme_classifier.h"
#include "chrome/browser/clair/window/clair_browser_window.h"
#include "chrome/browser/history/top_sites_factory.h"
#include "chrome/browser/profiles/profile.h"
#include "chrome/browser/search_engines/template_url_service_factory.h"
#include "chrome/browser/ui/browser.h"
#include "chrome/browser/ui/browser_window.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface.h"
#include "chrome/browser/ui/browser_window/public/browser_window_interface_iterator.h"
#include "chrome/browser/ui/navigator/browser_navigator.h"
#include "chrome/browser/ui/navigator/browser_navigator_params.h"
#include "chrome/browser/ui/tabs/tab_strip_model.h"
#include "chrome/browser/ui/tabs/tab_strip_user_gesture_details.h"
#include "components/favicon/content/content_favicon_driver.h"
#include "components/history/core/browser/top_sites.h"
#include "components/omnibox/browser/autocomplete_classifier.h"
#include "components/omnibox/browser/autocomplete_controller.h"
#include "components/omnibox/browser/autocomplete_controller_config.h"
#include "components/omnibox/browser/autocomplete_enums.h"
#include "components/omnibox/browser/autocomplete_input.h"
#include "components/omnibox/browser/autocomplete_match.h"
#include "components/omnibox/browser/autocomplete_provider.h"
#include "components/omnibox/browser/autocomplete_result.h"
#include "components/search_engines/template_url.h"
#include "components/search_engines/template_url_service.h"
#include "components/url_formatter/url_formatter.h"
#include "content/public/browser/web_contents.h"
#include "net/base/apple/url_conversions.h"
#include "third_party/metrics_proto/omnibox_event.pb.h"
#include "ui/base/page_transition_types.h"
#include "ui/base/window_open_disposition.h"
#include "ui/gfx/image/image.h"

namespace {

// Arc shows five rows (D11).
constexpr size_t kMaxSuggestions = 5;

// What a row opens and how, kept for -openSuggestion:.
struct Destination {
  GURL url;
  ui::PageTransition transition = ui::PAGE_TRANSITION_TYPED;
  // The tab it switches to instead, if any.
  base::WeakPtr<content::WebContents> tab;
  // The match it shows, for -deleteSuggestion:. Empty for the empty-query
  // rows, which don't come from the controller.
  std::optional<AutocompleteMatch> match;
};

}  // namespace

@interface ClairChromiumSuggestion : NSObject <ClairSuggestion>
@property(nonatomic) NSInteger suggestionID;
@property(nonatomic) ClairSuggestionKind kind;
@property(nonatomic, copy) NSString* contents;
@property(nonatomic, copy) NSString* descriptionText;
@property(nonatomic, copy, nullable) NSURL* destination;
@property(nonatomic, nullable) NSImage* icon;
@property(nonatomic) BOOL hasTabMatch;
@property(nonatomic, copy, nullable) NSString* keyword;
@property(nonatomic, copy, nullable) NSString* keywordName;
@property(nonatomic) BOOL canDelete;
@end

@implementation ClairChromiumSuggestion
@end

@interface ClairChromiumAutocomplete ()
- (void)resultChanged;
@end

namespace {

class ControllerObserver : public AutocompleteController::Observer {
 public:
  explicit ControllerObserver(ClairChromiumAutocomplete* session)
      : session_(session) {}

  void OnResultChanged(AutocompleteController* controller,
                       bool default_match_changed) override {
    [session_ resultChanged];
  }

 private:
  ClairChromiumAutocomplete* __weak session_;
};

ClairSuggestionKind KindOf(const AutocompleteMatch& match) {
  if (match.has_tab_match.value_or(false) ||
      match.type == omnibox::AutocompleteMatchType::kOpenTab) {
    return ClairSuggestionKindOpenTab;
  }
  if (AutocompleteMatch::IsSearchType(match.type)) {
    return ClairSuggestionKindSearch;
  }
  if (match.type == omnibox::AutocompleteMatchType::kUrlWhatYouTyped) {
    return ClairSuggestionKindURL;
  }
  return ClairSuggestionKindHistory;
}

}  // namespace

@implementation ClairChromiumAutocomplete {
  base::WeakPtr<ClairBrowserWindow> _browserWindow;
  ClairCommandBarMode _mode;
  id<ClairAutocompleteDelegate> __weak _delegate;
  std::unique_ptr<AutocompleteController> _controller;
  std::unique_ptr<ControllerObserver> _observer;
  std::vector<std::pair<NSInteger, Destination>> _destinations;
  NSInteger _nextSuggestionID;
  NSInteger _generation;
  BOOL _stopped;
  NSString* _keyword;
  NSString* _keywordName;
  NSArray<id<ClairSuggestion>>* _lastSuggestions;
}

- (instancetype)initWithBrowserWindow:(ClairBrowserWindow*)browserWindow
                                 mode:(ClairCommandBarMode)mode
                             delegate:(id<ClairAutocompleteDelegate>)delegate {
  if ((self = [super init])) {
    _mode = mode;
    _delegate = delegate;
    _nextSuggestionID = 1;
    if (browserWindow) {
      _browserWindow = browserWindow->GetWeakPtr();
      Profile* profile = browserWindow->browser()->GetProfile();
      AutocompleteControllerConfig config{
          .provider_types =
              AutocompleteClassifier::DefaultOmniboxProviders() &
              ~static_cast<int>(AutocompleteProvider::Type::kBookmark)};
      _controller = std::make_unique<AutocompleteController>(
          std::make_unique<ChromeAutocompleteProviderClient>(profile), config);
      _observer = std::make_unique<ControllerObserver>(self);
      _controller->AddObserver(_observer.get());
    }
  }
  return self;
}

- (void)dealloc {
  [self stop];
}

- (Profile*)profile {
  return _browserWindow ? _browserWindow->browser()->GetProfile() : nullptr;
}

- (NSString*)keyword {
  return _keyword;
}

- (NSString*)keywordName {
  return _keywordName;
}

- (NSImage*)keywordIcon {
  return nil;
}

- (NSInteger)rememberDestination:(Destination)destination {
  const NSInteger suggestionID = _nextSuggestionID++;
  _destinations.emplace_back(suggestionID, std::move(destination));
  return suggestionID;
}

- (void)startWithText:(const std::u16string&)text inKeywordMode:(bool)keywordMode {
  Profile* profile = self.profile;
  if (_stopped || !_controller || !profile) {
    return;
  }
  ++_generation;
  _controller->Stop(AutocompleteStopReason::kClobbered);
  const metrics::OmniboxEventProto::PageClassification classification =
      _mode == ClairCommandBarModeNewTab
          ? metrics::OmniboxEventProto::INSTANT_NTP_WITH_OMNIBOX_AS_STARTING_FOCUS
          : metrics::OmniboxEventProto::OTHER;
  AutocompleteInput input(text, classification,
                          ChromeAutocompleteSchemeClassifier(profile));
  // Arc fills nothing in.
  input.set_prevent_inline_autocomplete(true);
  input.set_in_keyword_mode(keywordMode);
  input.set_allow_exact_keyword_match(keywordMode);
  _controller->Start(input);
}

- (void)queryText:(NSString*)text {
  if (_stopped) {
    return;
  }
  std::u16string query = base::SysNSStringToUTF16(text);
  if (_keyword) {
    [self startWithText:base::StrCat({base::SysNSStringToUTF16(_keyword), u" ",
                                      query})
          inKeywordMode:true];
    return;
  }
  if (query.empty()) {
    [self showEmptyQueryList];
    return;
  }
  [self startWithText:query inKeywordMode:false];
}

- (void)acceptKeywordOfSuggestion:(NSInteger)suggestionID text:(NSString*)text {
  Profile* profile = self.profile;
  if (_stopped || !profile || !_controller) {
    return;
  }
  NSString* keyword = nil;
  for (id<ClairSuggestion> suggestion in _lastSuggestions) {
    if (suggestion.suggestionID == suggestionID) {
      keyword = suggestion.keyword;
    }
  }
  if (!keyword.length) {
    return;
  }
  TemplateURLService* service = TemplateURLServiceFactory::GetForProfile(profile);
  TemplateURL* engine =
      service ? service->GetTemplateURLForKeyword(base::SysNSStringToUTF16(keyword))
              : nullptr;
  _keyword = keyword;
  _keywordName = engine ? base::SysUTF16ToNSString(engine->short_name()) : keyword;
  [self queryText:text];
}

- (void)clearKeywordWithText:(NSString*)text {
  _keyword = nil;
  _keywordName = nil;
  [self queryText:text];
}

// D11: with an empty query, the window's other tabs by last use, then the profile's
// most visited sites. ungoogled-chromium's zero-suggest has no remote source,
// so this list is built here.
- (void)showEmptyQueryList {
  ++_generation;
  if (_controller) {
    _controller->Stop(AutocompleteStopReason::kClobbered);
  }
  _destinations.clear();
  NSMutableArray<id<ClairSuggestion>>* suggestions = [NSMutableArray array];
  if (_browserWindow) {
    TabStripModel* strip = _browserWindow->browser()->tab_strip_model();
    std::vector<content::WebContents*> tabs;
    // Switching to the tab already shown would do nothing.
    for (int i = 0; i < strip->count(); ++i) {
      if (i != strip->active_index()) {
        tabs.push_back(strip->GetWebContentsAt(i));
      }
    }
    std::ranges::sort(tabs, [](content::WebContents* a, content::WebContents* b) {
      return a->GetLastActiveTimeTicks() > b->GetLastActiveTimeTicks();
    });
    for (content::WebContents* tab : tabs) {
      ClairChromiumSuggestion* suggestion = [[ClairChromiumSuggestion alloc] init];
      suggestion.kind = ClairSuggestionKindOpenTab;
      suggestion.contents = base::SysUTF16ToNSString(tab->GetTitle());
      suggestion.descriptionText = base::SysUTF16ToNSString(
          url_formatter::FormatUrl(tab->GetLastCommittedURL()));
      suggestion.destination = net::NSURLWithGURL(tab->GetLastCommittedURL());
      suggestion.hasTabMatch = YES;
      if (auto* favicons = favicon::ContentFaviconDriver::FromWebContents(tab);
          favicons && favicons->FaviconIsValid()) {
        suggestion.icon = favicons->GetFavicon().ToNSImage();
      }
      suggestion.suggestionID =
          [self rememberDestination:Destination{tab->GetLastCommittedURL(),
                                                ui::PAGE_TRANSITION_AUTO_BOOKMARK,
                                                tab->GetWeakPtr()}];
      [suggestions addObject:suggestion];
    }
  }
  [self publish:suggestions finished:NO];

  Profile* profile = self.profile;
  scoped_refptr<history::TopSites> top_sites =
      profile ? TopSitesFactory::GetForProfile(profile) : nullptr;
  if (!top_sites) {
    [self publish:suggestions finished:YES];
    return;
  }
  const NSInteger generation = _generation;
  ClairChromiumAutocomplete* __weak weakSelf = self;
  NSArray<id<ClairSuggestion>>* tabSuggestions = [suggestions copy];
  top_sites->GetMostVisitedURLs(
      base::BindOnce(^(const history::MostVisitedURLList& sites) {
        [weakSelf addMostVisited:sites
                   toSuggestions:tabSuggestions
                      generation:generation];
      }));
}

- (void)addMostVisited:(const history::MostVisitedURLList&)sites
         toSuggestions:(NSArray<id<ClairSuggestion>>*)tabs
            generation:(NSInteger)generation {
  if (_stopped || generation != _generation) {
    return;
  }
  NSMutableArray<id<ClairSuggestion>>* suggestions = [tabs mutableCopy];
  for (const history::MostVisitedURL& site : sites) {
    if (suggestions.count >= tabs.count + kMaxSuggestions) {
      break;
    }
    ClairChromiumSuggestion* suggestion = [[ClairChromiumSuggestion alloc] init];
    suggestion.kind = ClairSuggestionKindHistory;
    suggestion.contents = base::SysUTF16ToNSString(
        site.title.empty() ? url_formatter::FormatUrl(site.url) : site.title);
    suggestion.descriptionText =
        base::SysUTF16ToNSString(url_formatter::FormatUrl(site.url));
    suggestion.destination = net::NSURLWithGURL(site.url);
    suggestion.suggestionID = [self
        rememberDestination:Destination{site.url, ui::PAGE_TRANSITION_AUTO_BOOKMARK,
                                        nullptr}];
    [suggestions addObject:suggestion];
  }
  [self publish:suggestions finished:YES];
}

- (void)resultChanged {
  if (_stopped || !_controller) {
    return;
  }
  _destinations.clear();
  NSMutableArray<id<ClairSuggestion>>* suggestions = [NSMutableArray array];
  Profile* profile = self.profile;
  TemplateURLService* service =
      profile ? TemplateURLServiceFactory::GetForProfile(profile) : nullptr;
  for (const AutocompleteMatch& match : _controller->result()) {
    if (suggestions.count >= kMaxSuggestions) {
      break;
    }
    if (!match.destination_url.is_valid()) {
      continue;
    }
    ClairChromiumSuggestion* suggestion = [[ClairChromiumSuggestion alloc] init];
    suggestion.kind = KindOf(match);
    suggestion.contents = base::SysUTF16ToNSString(match.contents);
    suggestion.descriptionText = base::SysUTF16ToNSString(match.description);
    suggestion.destination = net::NSURLWithGURL(match.destination_url);
    suggestion.hasTabMatch = match.has_tab_match.value_or(false);
    if (!match.associated_keyword.empty()) {
      suggestion.keyword = base::SysUTF16ToNSString(match.associated_keyword);
      TemplateURL* engine =
          service ? service->GetTemplateURLForKeyword(match.associated_keyword)
                  : nullptr;
      suggestion.keywordName =
          engine ? base::SysUTF16ToNSString(engine->short_name())
                 : suggestion.keyword;
    }
    suggestion.canDelete = match.SupportsDeletion();
    suggestion.suggestionID = [self
        rememberDestination:Destination{match.destination_url, match.transition,
                                        nullptr, match}];
    [suggestions addObject:suggestion];
  }
  [self publish:suggestions finished:_controller->done()];
}

- (void)deleteSuggestion:(NSInteger)suggestionID {
  if (_stopped || !_controller) {
    return;
  }
  auto found = std::ranges::find_if(
      _destinations, [&](const auto& entry) { return entry.first == suggestionID; });
  if (found == _destinations.end() || !found->second.match ||
      !found->second.match->SupportsDeletion()) {
    return;
  }
  // A copy: Chromium sends the shorter list during the call, which replaces
  // _destinations. Providers find what to delete by its URL or contents.
  const AutocompleteMatch match = *found->second.match;
  _controller->DeleteMatch(match);
}

- (void)publish:(NSArray<id<ClairSuggestion>>*)suggestions finished:(BOOL)finished {
  _lastSuggestions = [suggestions copy];
  [_delegate autocomplete:self
      didUpdateSuggestions:_lastSuggestions
                  finished:finished];
}

// Activates the tab of this profile showing `url`, in its window.
- (BOOL)switchToTab:(const Destination&)destination {
  content::WebContents* target = destination.tab.get();
  Profile* profile = self.profile;
  bool switched = false;
  ForEachCurrentBrowserWindowInterfaceOrderedByActivation(
      [&](BrowserWindowInterface* browser) {
        if (browser->GetProfile() != profile) {
          return true;
        }
        TabStripModel* strip = browser->GetTabStripModel();
        for (int i = 0; i < strip->count(); ++i) {
          content::WebContents* contents = strip->GetWebContentsAt(i);
          if (target ? contents == target
                     : contents->GetLastCommittedURL() == destination.url) {
            strip->ActivateTabAt(
                i, TabStripUserGestureDetails(
                       TabStripUserGestureDetails::GestureType::kOther));
            browser->GetWindow()->Activate();
            switched = true;
            return false;
          }
        }
        return true;
      });
  return switched;
}

- (void)openSuggestion:(NSInteger)suggestionID
           disposition:(ClairOpenDisposition)disposition {
  if (_stopped || !_browserWindow) {
    return;
  }
  auto found = std::ranges::find_if(
      _destinations, [&](const auto& entry) { return entry.first == suggestionID; });
  if (found == _destinations.end()) {
    return;
  }
  const Destination destination = found->second;
  BOOL hasTabMatch = destination.tab.get() != nullptr;
  for (id<ClairSuggestion> suggestion in _lastSuggestions) {
    if (suggestion.suggestionID == suggestionID && suggestion.hasTabMatch) {
      hasTabMatch = YES;
    }
  }
  Browser* browser = _browserWindow->browser();
  [self stop];
  if (hasTabMatch && [self switchToTab:destination]) {
    return;
  }
  NavigateParams params(browser, destination.url, destination.transition);
  switch (disposition) {
    case ClairOpenDispositionCurrentTab:
      params.disposition = WindowOpenDisposition::CURRENT_TAB;
      break;
    case ClairOpenDispositionNewForegroundTab:
      params.disposition = WindowOpenDisposition::NEW_FOREGROUND_TAB;
      break;
    case ClairOpenDispositionNewBackgroundTab:
      params.disposition = WindowOpenDisposition::NEW_BACKGROUND_TAB;
      break;
    case ClairOpenDispositionNewWindow:
      params.disposition = WindowOpenDisposition::NEW_WINDOW;
      break;
  }
  params.window_action = NavigateParams::WindowAction::kShowWindow;
  Navigate(&params);
}

- (void)stop {
  if (_stopped) {
    return;
  }
  _stopped = YES;
  if (_controller) {
    _controller->Stop(AutocompleteStopReason::kInteraction);
    _controller->RemoveObserver(_observer.get());
  }
  _observer.reset();
  _controller.reset();
  _delegate = nil;
}

@end
