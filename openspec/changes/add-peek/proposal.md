# Proposal

## Why

Arc users open links in Peek all the time: Shift+click shows the link in a card over the current page, which they read and then dismiss, or keep as a tab. Peek is on the MVP list in `ship-plain-ungoogled-build`'s roadmap. Today Shift+click in Clair opens Chromium's new window, which is the opposite of what Arc users expect. Arc stops working on 2026-12-22.

## What Changes

- **Shift+click opens a Peek.** Shift+clicking a link in a page opens it in a Peek over that tab's page, in place of a new window. Arc also opens Peeks for links to other sites from pinned tabs and favorites; Clair has neither yet, so Shift+click is the only trigger for now.
- **The Peek, as in Arc.** A rounded card centred over the page card, about 80% of its width and nearly its full height, grows out of the click point. The parent page shrinks slightly behind it and washes out. Close and Expand buttons sit in a column outside the card's top-trailing corner. Arc's third button, Open in Split View, waits for split view.
- **A Peek belongs to its tab.** The tab's row in the sidebar shows the Peek's favicon as a badge. The sidebar stays usable while a Peek is open: selecting another tab, by click or Ctrl+Tab, leaves the Peek where it is, and coming back shows it again. While the Peek shows, the URL field, back, forward, reload, find and DevTools act on the Peek's page.
- **Closing a Peek.** The × button, Cmd+W, a click on the washed-out parent page, or Esc closes it and returns to the parent unchanged. When the page keeps Esc for itself, as a site's own dialog does, the × turns into a red "Confirm" pill for about a second, and a second Esc closes the Peek. Closing the parent tab closes its Peek. Peeks close when Clair quits and are never restored.
- **Expanding a Peek.** Expand turns the Peek into a normal tab, with its history, directly below its parent in the sidebar. This is an exception to new tabs going to the top.
- **Links inside a Peek.** A plain click navigates within the Peek. Shift+click inside a Peek opens a normal new tab at the top of the sidebar.
- **A Links page in Settings.** It has the toggle "Open a Peek window when clicking on links with Shift held", on by default, as in Arc. With it off, Shift+click opens a new window, as in Chromium.
- **BREAKING (`ClairHost.h`):** `ClairTab` gains the tab's Peek, `ClairBrowser` gains calls to close and expand a Peek, and `ClairWindow` learns when the page kept Esc.

**Out of scope:**
- Peek for links to other sites from pinned tabs and favorites, which don't exist yet.
- Open in Split View, until split view exists.
- A Peek inside a Peek.
- Arc's Little Arc and its "Choose where links open" rules.

## Capabilities

### New Capabilities

- `peek`: opening a link in a Peek over its tab's page, how the Peek looks and animates, how it's closed and expanded, and its life alongside its parent tab.

### Modified Capabilities

- `sidebar`:
  - "Tab list" doesn't list Peeks, badges a tab that has one, and selecting that tab shows its Peek.
  - "New tabs at the top" makes an expanded Peek the exception.
  - "Closing, reordering and tab menu": closing a tab closes its Peek, and moving a tab moves its Peek with it.
- `browser-window`:
  - "Page shown in the card" shows the Peek over its parent.
  - "Link status" shows the capsule at the Peek's corner while the Peek shows.
- `settings-window`: "Settings pages" adds Links between General and Advanced, with a new Peek toggle requirement.

## Impact

- **Native layer:** a new Peek view in `native/ClairUI/` (card, buttons, Confirm pill, animation), `PageCardView.swift`, `SidebarView.swift` and `TabListLogic.swift` (hidden Peek tabs, the badge, the tab order Ctrl+Tab and Cmd+1–9 use), `SettingsWindow.swift` (Links page), `FakeBrowser` and unit tests in `native/ClairUITests/`.
- **Contract and engine:** `native/ClairHost.h`. New code in `overlay/chrome/browser/clair/window/` (Peek bookkeeping, the tab-selection commands, Esc). A hook in `BrowserWebContentsDelegate::OpenURLFromTab` and `AddNewContents`, added to `patches/clair/native-window-hook.patch`. The engine key changes, so `engine.yml` builds one new engine.
- **Tests:** runtime tests in `tests/runtime/` for opening, closing, expanding and quitting with a Peek.
- **Users:** a Changie fragment.
