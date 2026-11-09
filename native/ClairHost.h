// Copyright 2026 The Clair Authors
// You can use, redistribute, and/or modify this source code under
// the terms of the GPL-3.0 license that can be found in the LICENSE file.
//
// ClairHost.h: the one contract between Chromium and Clair's native layer,
// ClairUI.framework (change 1, native-layer spec and design D4; the window
// contract is replace-browser-window's design D3).
//
// Chromium loads ClairUI.framework from Clair.app/Contents/Frameworks once it
// has built the main menu, takes the bundle's principal class, checks that it
// conforms to ClairUIEntryPoint, and calls +startWithHost: with its
// implementation of ClairHost. From then on, Chromium asks the entry point for
// a ClairWindow for every normal browser window it creates (+windowForBrowser:),
// handing it a ClairBrowser. ClairUI reaches Chromium only through the host and
// those browsers, and Chromium reaches ClairUI only through the entry point and
// the windows it returns.
//
// The header is plain Objective-C, so Chromium includes it from Objective-C++
// and Swift imports it as the ClairHost module (native/module.modulemap).
// Every call happens on the main thread.
//
// Rules for the window contract:
// - Push, coalesced. Chromium tells each ClairWindow what changed, at most once
//   per run-loop turn for each tab. ClairUI never polls.
// - Snapshots, not pointers. Tabs, suggestions, downloads, extension actions
//   and infobars reach ClairUI as immutable value objects with IDs. A command
//   naming an ID that no longer exists does nothing.
// - Closing. ClairUI never closes a browser window itself: it calls
//   -requestClose, which runs Chromium's beforeunload flow. Chromium tells the
//   ClairWindow -browserDidClose when the window really closes, and the
//   ClairBrowser then ignores every call.
// - Activation. ClairUI never activates the app or orders the window front;
//   Chromium shows and activates its windows itself.
//
// It is an engine input (scripts/engine-key.sh): a change here needs a new
// engine, so keep it small and add to it only what ClairUI needs.

#ifndef CLAIR_NATIVE_CLAIR_HOST_H_
#define CLAIR_NATIVE_CLAIR_HOST_H_

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// Why relaunching Clair now, without asking, would interrupt the user. Each
// set bit is one reason; none set means a silent relaunch is safe.
typedef NS_OPTIONS(NSUInteger, ClairRelaunchBlockers) {
  ClairRelaunchBlockersNone = 0,
  // A download is in progress; quitting would cancel it.
  ClairRelaunchBlockersDownloadInProgress = 1 << 0,
  // An incognito window is open; it doesn't come back after a relaunch.
  ClairRelaunchBlockersIncognitoWindow = 1 << 1,
  // A tab is playing sound.
  ClairRelaunchBlockersAudibleTab = 1 << 2,
  // A tab is capturing the camera, microphone or screen.
  ClairRelaunchBlockersCapturingTab = 1 << 3,
} NS_SWIFT_NAME(RelaunchBlockers);

// What Chromium does for ClairUI. Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairHost)
@protocol ClairHost <NSObject>

// The Chromium version compiled into the engine, such as "156.0.8078.73".
// It is also what websites and extensions see.
@property(nonatomic, readonly, copy) NSString *chromiumVersion;

// The ungoogled-chromium release the engine was built from, such as
// "156.0.8078.73-1".
@property(nonatomic, readonly, copy) NSString *ungoogledChromiumVersion;

// What would make a relaunch without asking interrupt the user right now.
- (ClairRelaunchBlockers)silentRelaunchBlockers;

// Quits and reopens Clair through Chromium's own graceful relaunch, which
// restores the open windows and tabs. Chromium's quit confirmations still
// apply, so the user can cancel, for example while a download is running.
- (void)relaunch;

// Tells Chromium that Sparkle's installer is waiting for Clair to quit and will
// then replace the app. From now on, any relaunch reopens Clair only once that
// has happened, so the new version opens, and opens once.
- (void)updateWillInstallOnQuit;

// Opens `url`, chrome:// URLs included, in a new foreground tab of the most
// recently active browser window, or in a new browser window if none is open.
- (void)openURL:(NSURL *)url NS_SWIFT_NAME(open(_:));

@end

// ---------------------------------------------------------------------------
// The window contract (replace-browser-window design D3).
// ---------------------------------------------------------------------------

// A tab's ID: Chromium's tab handle, stable for the tab's lifetime and never
// reused while Clair runs.
typedef NSInteger ClairTabID NS_SWIFT_NAME(TabID);

// No tab, as in a window whose last tab is closing.
static const ClairTabID ClairTabIDNone = -1;

// The kind of profile a browser window shows.
typedef NS_ENUM(NSInteger, ClairProfileKind) {
  ClairProfileKindRegular = 0,
  // An off-the-record profile: the window uses a dark appearance and says
  // "Incognito" in its sidebar.
  ClairProfileKindIncognito = 1,
  // A guest profile.
  ClairProfileKindGuest = 2,
} NS_SWIFT_NAME(ProfileKind);

// What a tab is doing that the URL field shows as indicators. Each set bit is
// one indicator.
typedef NS_OPTIONS(NSUInteger, ClairTabIndicators) {
  ClairTabIndicatorsNone = 0,
  // The page is capturing the camera.
  ClairTabIndicatorsCamera = 1 << 0,
  // The page is capturing the microphone.
  ClairTabIndicatorsMicrophone = 1 << 1,
  // The page is using the user's location.
  ClairTabIndicatorsLocation = 1 << 2,
  // The page is capturing the screen, a window or a tab.
  ClairTabIndicatorsScreenCapture = 1 << 3,
  // A permission request from the page was blocked.
  ClairTabIndicatorsBlockedPermission = 1 << 4,
} NS_SWIFT_NAME(TabIndicators);

// Where something chosen in the window opens.
typedef NS_ENUM(NSInteger, ClairOpenDisposition) {
  // Navigates the active tab.
  ClairOpenDispositionCurrentTab = 0,
  // Opens a new active tab, at the top of the tab list.
  ClairOpenDispositionNewForegroundTab = 1,
  // Opens a new tab at the top of the tab list, leaving the active tab active.
  ClairOpenDispositionNewBackgroundTab = 2,
  // Opens a new browser window.
  ClairOpenDispositionNewWindow = 3,
} NS_SWIFT_NAME(OpenDisposition);

// Why the command bar is open.
typedef NS_ENUM(NSInteger, ClairCommandBarMode) {
  // Cmd+T, File > New Tab or the sidebar's "New Tab" row: opens empty, and
  // the choice opens in a new tab.
  ClairCommandBarModeNewTab = 0,
  // Cmd+L or a click on the URL field: opens on the active tab's full URL,
  // and the choice navigates the active tab.
  ClairCommandBarModeCurrentTab = 1,
} NS_SWIFT_NAME(CommandBarMode);

// The side DevTools is docked to in the card.
typedef NS_ENUM(NSInteger, ClairDevToolsDockSide) {
  // Not docked: DevTools is in its own window, or closed.
  ClairDevToolsDockSideNone = 0,
  ClairDevToolsDockSideRight = 1,
  ClairDevToolsDockSideBottom = 2,
  ClairDevToolsDockSideLeft = 3,
} NS_SWIFT_NAME(DevToolsDockSide);

// How the active tab's docked DevTools and its page share the card. This is
// Chromium's DevToolsContentsResizingStrategy: DevTools fills the card, and
// the page sits on top of it at `pageBounds`, as
// ApplyDevToolsContentsResizingStrategy() lays them out.
typedef struct NS_SWIFT_NAME(DevToolsLayout) {
  ClairDevToolsDockSide dockSide;
  // The page's bounds within the card, in points, with the origin at the
  // card's top-left corner. Empty, with `hidesPage` false, means that the
  // page fills the card.
  NSRect pageBounds;
  // DevTools asks for the page to be hidden.
  bool hidesPage;
} ClairDevToolsLayout;

// The state of find in page in the active tab.
typedef struct NS_SWIFT_NAME(FindResult) {
  // The 1-based position of the selected match, or 0 when there's none.
  NSInteger activeMatch;
  // How many matches the page has so far.
  NSInteger matchCount;
  // Whether the search has finished; until then, `matchCount` may grow.
  bool finished;
} ClairFindResult;

// A surface in the window that Chromium's bubbles attach to.
typedef NS_ENUM(NSInteger, ClairAnchorKind) {
  // The URL field's site-controls button: page info and permission prompts.
  ClairAnchorKindSiteControls = 0,
  // One of the URL field's indicators, named by the matching
  // ClairTabIndicators value.
  ClairAnchorKindIndicator = 1,
  // A pinned extension action's button, named by its extension ID.
  ClairAnchorKindExtensionAction = 2,
  // The extensions button, for extensions that aren't pinned.
  ClairAnchorKindExtensionsButton = 3,
  // The downloads button.
  ClairAnchorKindDownloads = 4,
} NS_SWIFT_NAME(AnchorKind);

// The edge of an anchor rectangle that a bubble attaches to.
typedef NS_ENUM(NSInteger, ClairAnchorEdge) {
  // The rectangle's trailing edge: a control in the sidebar, with the bubble
  // to its right.
  ClairAnchorEdgeTrailing = 0,
  // The rectangle's bottom edge: the card's top-leading corner, used while the
  // sidebar is hidden, revealed as an overlay, or the window is in full screen.
  ClairAnchorEdgeBottom = 1,
} NS_SWIFT_NAME(AnchorEdge);

// Where a bubble attaches.
typedef struct NS_SWIFT_NAME(BubbleAnchor) {
  // The rectangle, in the window's coordinates (origin at the bottom left).
  NSRect rect;
  ClairAnchorEdge edge;
} ClairAnchor;

// What the user chose in an infobar.
typedef NS_ENUM(NSInteger, ClairInfobarAction) {
  ClairInfobarActionOK = 0,
  ClairInfobarActionCancel = 1,
  ClairInfobarActionLink = 2,
  // The infobar's close button.
  ClairInfobarActionDismiss = 3,
} NS_SWIFT_NAME(InfobarAction);

// What a suggestion in the command bar is.
typedef NS_ENUM(NSInteger, ClairSuggestionKind) {
  // A search with the default search engine, or with a keyword's engine.
  ClairSuggestionKindSearch = 0,
  // A URL as typed.
  ClairSuggestionKindURL = 1,
  // A page from history or the most visited sites.
  ClairSuggestionKindHistory = 2,
  // A tab open in this profile.
  ClairSuggestionKindOpenTab = 3,
} NS_SWIFT_NAME(SuggestionKind);

// Where a download is.
typedef NS_ENUM(NSInteger, ClairDownloadState) {
  ClairDownloadStateInProgress = 0,
  ClairDownloadStatePaused = 1,
  ClairDownloadStateComplete = 2,
  ClairDownloadStateCancelled = 3,
  // Failed, for example because the network dropped; it may be resumable.
  ClairDownloadStateInterrupted = 4,
} NS_SWIFT_NAME(DownloadState);

// The whole app's download progress, as the Dock shows it: the running
// downloads of every profile, paused ones included.
typedef struct {
  // How many downloads are running; with none, there's no progress to show.
  NSInteger count;
  // Whether any of them has an unknown size. The Dock then shows no ring.
  bool isIndeterminate;
  // Bytes received over bytes expected, for the downloads of known size.
  double fraction;
} ClairDownloadProgress NS_SWIFT_NAME(DownloadProgress);

// An infobar on a tab, such as "Clair is being controlled by automated test
// software" or an extension debugging the browser. Chromium implements it as
// a snapshot.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairInfobar)
@protocol ClairInfobar <NSObject>
// Unique among the tab's infobars while it shows.
@property(nonatomic, readonly) NSInteger infobarID;
// The infobar's text.
@property(nonatomic, readonly, copy) NSString *message;
// The link after the message, if it has one.
@property(nonatomic, readonly, copy, nullable) NSString *linkText;
// The default button's label, if it has one.
@property(nonatomic, readonly, copy, nullable) NSString *okButtonLabel;
// The other button's label, if it has one.
@property(nonatomic, readonly, copy, nullable) NSString *cancelButtonLabel;
// The icon before the message, if it has one.
@property(nonatomic, readonly, nullable) NSImage *icon;
@end

// A tab, as a snapshot of its state when Chromium posted it. Chromium
// implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairTab)
@protocol ClairTab <NSObject>
@property(nonatomic, readonly) ClairTabID tabID;
// The page's title, or what Chromium shows for a page without one.
@property(nonatomic, readonly, copy) NSString *title;
// The URL the tab shows, which is the pending URL while a navigation the user
// started hasn't committed, or nil when it has none or isn't a valid NSURL.
@property(nonatomic, readonly, copy, nullable) NSURL *url;
// The full URL formatted for people, as Chromium's omnibox shows it while
// editing: unescaped, with internationalized domain names in Unicode.
@property(nonatomic, readonly, copy) NSString *urlText;
// The URL's host formatted for people, with internationalized domain names in
// Unicode, or nil when the URL has no host.
@property(nonatomic, readonly, copy, nullable) NSString *displayHost;
// Whether the tab shows the new tab page.
@property(nonatomic, readonly) BOOL isNewTabPage;
// The page's favicon, or nil while it has none, as on the new tab page.
@property(nonatomic, readonly, nullable) NSImage *favicon;
// Whether the tab is loading a new document in its main frame, the state in
// which Chromium's toolbar shows stop and its tab strip a spinner
// (WebContents::IsLoading() && ShouldShowLoadingUI()). A frame loading on its
// own or a same-document navigation doesn't count.
@property(nonatomic, readonly) BOOL isLoading;
// How far that load has got, from 0 to 1 (WebContents::GetLoadProgress()).
// Only meaningful while `isLoading`.
@property(nonatomic, readonly) double loadProgress;
// Whether back and forward can go anywhere.
@property(nonatomic, readonly) BOOL canGoBack;
@property(nonatomic, readonly) BOOL canGoForward;
// Whether the tab is playing sound, or has recently.
@property(nonatomic, readonly) BOOL isAudible;
// Whether the user muted the tab.
@property(nonatomic, readonly) BOOL isMuted;
// Whether the page's renderer crashed or was killed; the card shows the
// crashed-page view instead of the page.
@property(nonatomic, readonly) BOOL isCrashed;
// The indicators the URL field shows for the tab.
@property(nonatomic, readonly) ClairTabIndicators indicators;
// The tab's infobars, top first.
@property(nonatomic, readonly, copy) NSArray<id<ClairInfobar>> *infobars;
@end

// A suggestion in the command bar. Chromium implements it as a snapshot of an
// AutocompleteMatch.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairSuggestion)
@protocol ClairSuggestion <NSObject>
// Unique within its autocomplete session.
@property(nonatomic, readonly) NSInteger suggestionID;
// What it is, which picks its icon when it has none of its own.
@property(nonatomic, readonly) ClairSuggestionKind kind;
// The row's title: the page's title, or the search terms.
@property(nonatomic, readonly, copy) NSString *contents;
// The row's second line, such as the URL, or empty.
@property(nonatomic, readonly, copy) NSString *descriptionText;
// Where choosing it goes, or nil if Chromium can't express it as an NSURL.
@property(nonatomic, readonly, copy, nullable) NSURL *destination;
// The page's favicon or the engine's icon, or nil to use the kind's icon.
@property(nonatomic, readonly, nullable) NSImage *icon;
// Whether a tab of this profile already shows the destination; choosing the
// suggestion then switches to that tab.
@property(nonatomic, readonly) BOOL hasTabMatch;
// The keyword of the search engine the suggestion offers to search with Tab,
// such as "wiki", or nil.
@property(nonatomic, readonly, copy, nullable) NSString *keyword;
// That engine's name, such as "Wikipedia", or nil.
@property(nonatomic, readonly, copy, nullable) NSString *keywordName;
@end

// An extension's toolbar action. Chromium implements it as a snapshot.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairExtensionAction)
@protocol ClairExtensionAction <NSObject>
// The extension's ID, which names the action in commands.
@property(nonatomic, readonly, copy) NSString *extensionID;
// The action's title, which is its tooltip.
@property(nonatomic, readonly, copy) NSString *name;
// The action's icon for the active tab.
@property(nonatomic, readonly, nullable) NSImage *icon;
// The badge text for the active tab, or empty.
@property(nonatomic, readonly, copy) NSString *badgeText;
// The badge's colour, or nil for the default.
@property(nonatomic, readonly, nullable) NSColor *badgeBackgroundColor;
// Whether the user pinned it to the sidebar.
@property(nonatomic, readonly) BOOL isPinned;
// Whether it can run on the active tab.
@property(nonatomic, readonly) BOOL isEnabled;
// Whether running it opens a popup.
@property(nonatomic, readonly) BOOL hasPopup;
@end

// A download of the window's profile from this session. Chromium implements
// it as a snapshot.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairDownload)
@protocol ClairDownload <NSObject>
// Chromium's download GUID.
@property(nonatomic, readonly, copy) NSString *downloadID;
// The name of the file it saves to.
@property(nonatomic, readonly, copy) NSString *fileName;
@property(nonatomic, readonly) ClairDownloadState state;
// How much has arrived, in bytes.
@property(nonatomic, readonly) int64_t receivedBytes;
// The total size, or 0 when it isn't known.
@property(nonatomic, readonly) int64_t totalBytes;
// Whether Chromium needs the user to keep or discard it, as for a dangerous
// file type, and what it says about it.
@property(nonatomic, readonly) BOOL needsDecision;
@property(nonatomic, readonly, copy, nullable) NSString *warningText;
// Whether an interrupted download can be resumed.
@property(nonatomic, readonly) BOOL canResume;
// Whether the user has opened it or seen it in the downloads list since it
// finished.
@property(nonatomic, readonly) BOOL isSeen;
@end

@protocol ClairAutocomplete;

// What the command bar implements to hear from its autocomplete session.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairAutocompleteDelegate)
@protocol ClairAutocompleteDelegate <NSObject>
// The suggestions changed, best first. Results arrive over time; `finished`
// says that no more will come for the current query.
- (void)autocomplete:(id<ClairAutocomplete>)session
    didUpdateSuggestions:(NSArray<id<ClairSuggestion>> *)suggestions
                finished:(BOOL)finished
    NS_SWIFT_NAME(autocomplete(_:didUpdate:finished:));
@end

// One command bar session on Chromium's AutocompleteController for the
// window's profile (design D11). Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairAutocomplete)
@protocol ClairAutocomplete <NSObject>
// The search engine in keyword mode, after -acceptKeywordOfSuggestion:, or
// nil. Its name and icon show in the field.
@property(nonatomic, readonly, copy, nullable) NSString *keyword;
@property(nonatomic, readonly, copy, nullable) NSString *keywordName;
@property(nonatomic, readonly, nullable) NSImage *keywordIcon;

// Starts a query for `text`, replacing the one running. An empty `text` lists
// the window's tabs, most recently used first, then the most visited sites.
- (void)queryText:(NSString *)text NS_SWIFT_NAME(query(_:));

// Enters keyword mode for the suggestion's engine, as Tab does in the omnibox,
// and runs `text` against it.
- (void)acceptKeywordOfSuggestion:(NSInteger)suggestionID text:(NSString *)text
    NS_SWIFT_NAME(acceptKeyword(ofSuggestion:text:));

// Leaves keyword mode and runs `text` as a plain query.
- (void)clearKeywordWithText:(NSString *)text NS_SWIFT_NAME(clearKeyword(text:));

// Opens a suggestion from the latest results. A suggestion with a tab match
// switches to that tab instead, in its window.
- (void)openSuggestion:(NSInteger)suggestionID disposition:(ClairOpenDisposition)disposition
    NS_SWIFT_NAME(open(suggestion:disposition:));

// Ends the session. It sends nothing more, and ignores every later call.
- (void)stop;
@end

// Which way a history menu goes from the active tab's current page.
typedef NS_ENUM(NSInteger, ClairHistoryDirection) {
  ClairHistoryDirectionBack = 0,
  ClairHistoryDirectionForward = 1,
} NS_SWIFT_NAME(HistoryDirection);

// What an item in a history menu is.
typedef NS_ENUM(NSInteger, ClairHistoryItemKind) {
  // A page in the tab's history.
  ClairHistoryItemKindPage = 0,
  // "Show Full History", which opens Chromium's history page. It comes last,
  // after a separator, and only outside incognito.
  ClairHistoryItemKindShowFullHistory = 1,
} NS_SWIFT_NAME(HistoryItemKind);

// An item in a history menu. Chromium implements it as a snapshot.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairHistoryItem)
@protocol ClairHistoryItem <NSObject>
// Unique within its menu session; names the item in -openItem:disposition:.
@property(nonatomic, readonly) NSInteger itemID;
@property(nonatomic, readonly) ClairHistoryItemKind kind;
// The page's title, or its URL when it has none; the item's label.
@property(nonatomic, readonly, copy) NSString *title;
// The page's URL, or nil for "Show Full History".
@property(nonatomic, readonly, copy, nullable) NSURL *url;
// The page's favicon, or nil while it has none yet; it may arrive later
// through -historyMenu:itemsDidChange:. Always nil for "Show Full History".
@property(nonatomic, readonly, nullable) NSImage *icon;
@end

@protocol ClairHistoryMenu;

// What ClairUI implements to hear from a history menu session.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairHistoryMenuDelegate)
@protocol ClairHistoryMenuDelegate <NSObject>
// The items changed: a favicon arrived, or the tab navigated. `items` is the
// whole list, which is empty when the tab can no longer go that way.
- (void)historyMenu:(id<ClairHistoryMenu>)menu itemsDidChange:(NSArray<id<ClairHistoryItem>> *)items
    NS_SWIFT_NAME(historyMenu(_:itemsDidChange:));
@end

// One back or forward history menu on Chromium's BackForwardMenuModel for the
// active tab (arc-navigation-feedback design D3). Chromium implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairHistoryMenu)
@protocol ClairHistoryMenu <NSObject>
// The pages in the session's direction, nearest first, up to Chromium's own
// menu's limit, then "Show Full History".
@property(nonatomic, readonly, copy) NSArray<id<ClairHistoryItem>> *items;
// Goes to an item's page in the active tab, or opens it as `disposition`
// says, as choosing it in Chromium's menu would. "Show Full History" ignores
// `disposition`. It ends the session.
- (void)openItem:(NSInteger)itemID disposition:(ClairOpenDisposition)disposition
    NS_SWIFT_NAME(open(item:disposition:));
// Ends the session without choosing. It sends nothing more, and ignores every
// later call.
- (void)close;
@end

// Where the window's close, minimize and zoom buttons go. The window ClairBrowser
// hands over adopts it, and AppKit's own title bar layout puts the buttons
// there, so no later title bar layout moves them. ClairUI sets it as the
// sidebar moves.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairWindowControls)
@protocol ClairWindowControls <NSObject>

// The close button's top-leading corner, from the window's top-leading corner,
// in points. The other buttons follow at AppKit's spacing.
@property(nonatomic) CGPoint windowControlsOrigin;

// Whether the buttons are hidden, as while the sidebar is hidden or a page is
// in full screen.
@property(nonatomic) BOOL windowControlsHidden;

@end

// One native browser window's browser: its tabs, pages and commands. Chromium
// implements it, one per native window, and keeps owning the browser.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairBrowser)
@protocol ClairBrowser <NSObject>

// The window Chromium created for this browser, which ClairUI styles and fills.
// It dispatches Chromium's commands and key equivalents, and adopts
// ClairWindowControls.
@property(nonatomic, readonly) NSWindow<ClairWindowControls> *window;

// The kind of profile the window's tabs use.
@property(nonatomic, readonly) ClairProfileKind profileKind;

// The window's tabs, in Chromium's tab strip order, which is the sidebar's.
@property(nonatomic, readonly, copy) NSArray<id<ClairTab>> *tabs;

// The active tab, or ClairTabIDNone.
@property(nonatomic, readonly) ClairTabID activeTabID;

// The view holding a tab's page, or nil for an unknown tab. The card shows the
// active tab's view.
- (nullable NSView *)pageViewForTab:(ClairTabID)tabID NS_SWIFT_NAME(pageView(for:));

// The active tab's docked DevTools view, or nil when DevTools isn't docked,
// and how it shares the card with the page.
@property(nonatomic, readonly, nullable) NSView *devToolsView;
@property(nonatomic, readonly) ClairDevToolsLayout devToolsLayout;

// The extensions with an action, pinned ones first in the user's order.
@property(nonatomic, readonly, copy) NSArray<id<ClairExtensionAction>> *extensionActions;

// The window's profile's downloads from this session, newest first.
@property(nonatomic, readonly, copy) NSArray<id<ClairDownload>> *downloads;
// The whole app's download progress, as the Dock shows it.
@property(nonatomic, readonly) ClairDownloadProgress downloadProgress;

// --- Tabs ---
// Makes the tab active.
- (void)activateTab:(ClairTabID)tabID NS_SWIFT_NAME(activate(tab:));
// Closes the tab, with its leave-page confirmation.
- (void)closeTab:(ClairTabID)tabID NS_SWIFT_NAME(close(tab:));
// Closes every tab below it, each with its leave-page confirmation.
- (void)closeTabsBelowTab:(ClairTabID)tabID NS_SWIFT_NAME(closeTabs(below:));
// Moves the tab to `index` in the tab order.
- (void)moveTab:(ClairTabID)tabID toIndex:(NSInteger)index NS_SWIFT_NAME(move(tab:to:));
// Opens a copy of the tab, with its history, as Chromium's Duplicate does.
- (void)duplicateTab:(ClairTabID)tabID NS_SWIFT_NAME(duplicate(tab:));
// Mutes or unmutes the tab.
- (void)setMuted:(BOOL)muted forTab:(ClairTabID)tabID NS_SWIFT_NAME(setMuted(_:tab:));

// --- Navigation of the active tab: back, forward, reload (which also
// reloads a crashed page) and stop ---
- (void)goBack;
- (void)goForward;
- (void)reload;
- (void)stop;

// Opens `url`, chrome:// URLs included.
- (void)openURL:(NSURL *)url disposition:(ClairOpenDisposition)disposition
    NS_SWIFT_NAME(open(_:disposition:));

// Starts a command bar session. Chromium keeps `delegate` weakly.
- (id<ClairAutocomplete>)startAutocompleteWithMode:(ClairCommandBarMode)mode
                                          delegate:(id<ClairAutocompleteDelegate>)delegate
    NS_SWIFT_NAME(startAutocomplete(mode:delegate:));

// Starts a history menu session for the active tab, or returns nil when the
// tab can't go that way. Chromium keeps `delegate` weakly. ClairUI starts one
// when the user opens the back or forward button's menu and closes it when
// the menu closes.
- (nullable id<ClairHistoryMenu>)startHistoryMenuWithDirection:(ClairHistoryDirection)direction
                                                      delegate:(id<ClairHistoryMenuDelegate>)delegate
    NS_SWIFT_NAME(startHistoryMenu(direction:delegate:));

// Gives the active tab's page keyboard focus, as when the command bar or find
// closes.
- (void)focusPage;

// --- Find in page, in the active tab ---
// Finds `text`, or the next match in `forward` direction when it's the same
// text as before. Results arrive through -[ClairWindow findResultDidChange:].
- (void)findText:(NSString *)text forward:(BOOL)forward NS_SWIFT_NAME(find(_:forward:));
// Ends find: clears the highlights and keeps the selected match selected.
- (void)stopFinding;

// --- Site controls ---
// Opens Chromium's page info for the active tab, attached to the site controls
// or to one indicator (`indicator` is ignored for other kinds).
- (void)showPageInfoAtAnchor:(ClairAnchorKind)kind indicator:(ClairTabIndicators)indicator
    NS_SWIFT_NAME(showPageInfo(at:indicator:));

// --- Extensions ---
// Runs the action as Chromium's toolbar would. Its popup, if any, comes back
// through -[ClairWindow showExtensionPopup:...], attached to `anchor`, which is
// ClairAnchorKindExtensionAction or ClairAnchorKindExtensionsButton.
- (void)runExtensionAction:(NSString *)extensionID anchor:(ClairAnchorKind)anchor
    NS_SWIFT_NAME(runExtensionAction(_:anchor:));
// Pins the action to the sidebar, or unpins it.
- (void)setExtensionAction:(NSString *)extensionID pinned:(BOOL)pinned
    NS_SWIFT_NAME(setExtensionAction(_:pinned:));
// The popup's popover closed, for example because the user clicked outside it.
- (void)extensionPopupDidClose;

// --- Downloads: open a finished one in its default app (which counts as
// seen), reveal it in Finder, cancel it, or resume an interrupted one ---
- (void)openDownload:(NSString *)downloadID NS_SWIFT_NAME(openDownload(_:));
- (void)showDownloadInFinder:(NSString *)downloadID NS_SWIFT_NAME(showDownloadInFinder(_:));
- (void)cancelDownload:(NSString *)downloadID NS_SWIFT_NAME(cancelDownload(_:));
- (void)resumeDownload:(NSString *)downloadID NS_SWIFT_NAME(resumeDownload(_:));
// For a download that needs a decision: keep or discard it.
- (void)keepDownload:(NSString *)downloadID NS_SWIFT_NAME(keepDownload(_:));
- (void)discardDownload:(NSString *)downloadID NS_SWIFT_NAME(discardDownload(_:));
// The user looked at the downloads list: finished downloads count as seen.
- (void)markDownloadsSeen;

// --- Infobars ---
// The user chose one of the infobar's buttons, its link or its close button.
- (void)infobar:(NSInteger)infobarID ofTab:(ClairTabID)tabID didChoose:(ClairInfobarAction)action
    NS_SWIFT_NAME(infobar(_:tab:didChoose:));

// --- The window ---
// The window's close button: runs Chromium's close flow, with its
// beforeunload prompts, which may keep the window open.
- (void)requestClose;

@end

// One native browser window, drawn by ClairUI. ClairUI implements it.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairWindow)
@protocol ClairWindow <NSObject>

// The view that holds the active page in the card. Tab-modal dialogs centre on
// it.
@property(nonatomic, readonly) NSView *pageContainerView;

// Whether the sidebar is hidden, for View > Hide Sidebar's title.
@property(nonatomic, readonly) BOOL isSidebarHidden;

// --- Tabs ---
// Tabs were added, closed or moved. `tabs` is the new list, in order.
- (void)tabsDidChange:(NSArray<id<ClairTab>> *)tabs NS_SWIFT_NAME(tabsDidChange(_:));
// One tab's state changed.
- (void)tabDidChange:(id<ClairTab>)tab NS_SWIFT_NAME(tabDidChange(_:));
// Another tab became active; its page view is -[ClairBrowser pageViewForTab:].
- (void)activeTabDidChange:(ClairTabID)tabID NS_SWIFT_NAME(activeTabDidChange(_:));
// The active tab's docked DevTools view or layout changed.
- (void)devToolsDidChange;

// --- Commands ---
// Opens the command bar.
- (void)showCommandBarWithMode:(ClairCommandBarMode)mode NS_SWIFT_NAME(showCommandBar(mode:));
// View > Hide Sidebar and Cmd+S.
- (void)toggleSidebar;

// --- Find ---
// Opens the find field holding `text`, all selected, and focuses it.
- (void)showFindWithText:(NSString *)text NS_SWIFT_NAME(showFind(text:));
// Closes the find field.
- (void)hideFind;
// The match count or the selected match changed.
- (void)findResultDidChange:(ClairFindResult)result NS_SWIFT_NAME(findResultDidChange(_:));

// --- What the card shows ---
// The URL of the link under the pointer, or nil to hide the status capsule.
- (void)statusTextDidChange:(nullable NSString *)text NS_SWIFT_NAME(statusTextDidChange(_:));
// Shows a short confirmation at the bottom of the card, such as "Image copied".
- (void)showToast:(NSString *)message NS_SWIFT_NAME(showToast(_:));
// The page asked for full screen, or left it: the card shows the page alone,
// with no sidebar, insets or corners. Chromium puts the window into macOS full
// screen itself.
- (void)pageFullscreenDidChange:(BOOL)fullscreen NS_SWIFT_NAME(pageFullscreenDidChange(_:));
// The exclusive-access notice, such as "Press Esc to exit full screen", or nil
// to hide it.
- (void)showExclusiveAccessNotice:(nullable NSString *)text NS_SWIFT_NAME(showExclusiveAccessNotice(_:));

// --- Chromium's bubbles ---
// Where a bubble for `kind` attaches now: the control in the sidebar, or the
// card's top-leading corner when the sidebar isn't shown in place.
// `indicator` names the indicator for ClairAnchorKindIndicator, and
// `extensionID` the action for ClairAnchorKindExtensionAction; other kinds
// ignore them. An indicator or action the sidebar doesn't show falls back to
// the site controls or the extensions button.
- (ClairAnchor)anchorForKind:(ClairAnchorKind)kind
                   indicator:(ClairTabIndicators)indicator
                 extensionID:(nullable NSString *)extensionID
    NS_SWIFT_NAME(anchor(for:indicator:extensionID:));

// --- Extensions ---
// The actions, pinned order, icons or badges changed.
- (void)extensionActionsDidChange:(NSArray<id<ClairExtensionAction>> *)actions
    NS_SWIFT_NAME(extensionActionsDidChange(_:));
// Shows an extension's popup page in a popover attached to `anchor`, at `size`.
- (void)showExtensionPopup:(NSView *)view
                      size:(NSSize)size
                 extension:(NSString *)extensionID
                    anchor:(ClairAnchorKind)anchor
    NS_SWIFT_NAME(showExtensionPopup(_:size:extension:anchor:));
// The popup page resized itself.
- (void)extensionPopupDidResize:(NSSize)size NS_SWIFT_NAME(extensionPopupDidResize(_:));
// Chromium closed the popup, for example because the extension called
// window.close().
- (void)closeExtensionPopup;

// --- Downloads ---
// One of the window's profile's downloads started, progressed, finished, or
// was opened or removed; the progress is the app-wide one at that moment.
- (void)downloadsDidChange:(NSArray<id<ClairDownload>> *)downloads
                  progress:(ClairDownloadProgress)progress NS_SWIFT_NAME(downloadsDidChange(_:progress:));
// The app-wide progress changed: a download of any profile, whether or not
// it has a window, started, progressed, paused or ended.
- (void)downloadProgressDidChange:(ClairDownloadProgress)progress NS_SWIFT_NAME(downloadProgressDidChange(_:));

// --- The window ---
// Chromium is closing the window. ClairUI lets go of its views and the
// browser; Chromium closes the NSWindow itself.
- (void)browserDidClose;

@end

// What ClairUI.framework's principal class (NSPrincipalClass) implements.
NS_SWIFT_UI_ACTOR
NS_SWIFT_NAME(ClairUIEntryPoint)
@protocol ClairUIEntryPoint <NSObject>

// Called once, after Chromium has built the main menu. ClairUI keeps `host`
// for as long as the app runs.
+ (void)startWithHost:(id<ClairHost>)host NS_SWIFT_NAME(start(host:));

// Called for every normal browser window Chromium creates, incognito and guest
// windows included, after +startWithHost:. ClairUI styles `browser.window`,
// fills it and returns the window, which Chromium keeps until it closes. It
// never returns nil: Chromium stops on a nil window rather than showing its
// own.
+ (id<ClairWindow>)windowForBrowser:(id<ClairBrowser>)browser NS_SWIFT_NAME(window(for:));

@end

NS_ASSUME_NONNULL_END

#endif  // CLAIR_NATIVE_CLAIR_HOST_H_
