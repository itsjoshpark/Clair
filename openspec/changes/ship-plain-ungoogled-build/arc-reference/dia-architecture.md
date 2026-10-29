# Dia: architecture and Chromium integration

Observed on 2026-10-28 by inspecting the installed bundles of Dia 1.54.2 (build 89247) and Arc 1.170.0 (build 89123) on macOS, with both apps running. Dia is The Browser Company's successor to Arc and was designed with hindsight from it, so **for how the app is built, Dia supersedes Arc as the reference**; Arc appears below only where the two differ. How Arc looks and behaves stays in `look-and-behaviour.md`, and Arc remains the product Clair emulates.

This is a record of what Dia does, not a template. Clair does not take Dia's AI features: the assistant, agents, skills, on-device models and the agent server are noted only so their parts of the bundle can be recognised and set aside.

Everything here comes from the shipped binaries: `Info.plist` files, framework and resource listings, `otool -L`, exported Objective-C symbols (`nm`), public headers shipped in the bundle, `codesign` entitlements, the process list and the files under `~/Library/Application Support/`. Dia is closed source, so internals not visible this way (the size of its Chromium patches, how the Swift UI is laid out) are not recorded.

## Summary

Dia is a native Swift (SwiftUI and AppKit) app that **owns the process and embeds Chromium as a library**. Chromium is built as `ArcCore.framework`, with Chrome's own UI left out, and exposes an Objective-C++ API that Swift imports as a module. Arc uses the same framework; in these builds it is the **same Chromium version and the same API** in both apps. On top of that, Dia moves its state into encrypted SQLite and adds AI features (on-device ML and a sandboxed local agent server), which are out of scope for Clair.

```
Dia.app
├── MacOS/Dia                      Swift app (arm64): UI, state, agent manager
├── Frameworks/
│   ├── ArcCore.framework          Chromium 156.0.8078.48 + ADK Objective-C++ API
│   │   ├── Headers/, Modules/     public API, `framework module ArcCore`
│   │   ├── Helpers/               Browser Helper (GPU/Renderer/Alerts/Aperitif …).app
│   │   └── Libraries/             libaperitif, SwiftShader, Vulkan
│   ├── libAIInfra.dylib,          on-device AI (out of scope)
│   │   libContentConversion.dylib
│   ├── GRDB, Lottie, Sentry, Sparkle
└── Resources/
    ├── BoostBrowser_*.bundle      51 Swift feature modules (Dia's own UI)
    ├── ARC_*, ARCClients_*, ARCFoundation, ARCUI   modules shared with Arc
    └── agent-server-resources/    AI agent server (out of scope)
```

## Identity

| | Dia | Arc |
|---|---|---|
| Bundle ID | `company.thebrowser.dia` | `company.thebrowser.Browser` |
| Version (build) | 1.54.2 (89247) | 1.170.0 (89123) |
| Architectures | arm64 only | x86_64 and arm64 |
| Minimum macOS | 14.0 | 13.0 |
| SDK / Xcode | macOS 26.4 SDK, Xcode 26.4.1 | same |
| Team ID | `S6N382Y83G` | same |
| Updates | Sparkle, feed `releases.diabrowser.com/BoostBrowser-updates.xml`, checks every 8 h, automatic | Sparkle, feed `releases.arc.net/updates.xml`; **same EdDSA public key** |
| Internal codename | `BoostBrowser` (module prefix and update feed name) | `ARC` |
| Document type | `company.thebrowser.supertab` (`.supertab`) | none |

## Chromium as a framework (`ArcCore.framework`)

- **Version:** Chromium 156.0.8078.48 in both apps. The framework's bundle ID is `company.thebrowser.browser.framework` in both.
- **One engine build for both products.** Both binaries export the same 146 `Arc*` Objective-C classes. `ArcBrowserApplicationConfiguration` takes an `ArcApplicationID` of `Arc` or `Dia`, so one engine build serves both apps and the host says which one it is at start-up.
- **Size:** 239 MB in Dia (arm64 only) and 502 MB in Arc (universal). That difference explains most of the gap in framework size (335 MB against 591 MB). The resources are the same: `resources.pak`, `chrome_100/200_percent.pak`, `icudtl.dat`, V8 snapshots, DevTools, and `arc/services/{ai,content_conversion}`.
- **Helpers** are Chromium's usual helper apps, renamed: `Browser Helper`, `(GPU)`, `(Renderer)` and `(Alerts)`, plus a second set called **Aperitif** (`Browser Helper (Aperitif)`, `(Aperitif GPU)`, `(Aperitif Renderer)`, `(Aperitif Alerts)`) backed by `Libraries/libaperitif.dylib`, which links `libsandbox`. What Aperitif is for was not established.
- **Process tree at runtime:** `Dia` is the parent of every Browser Helper process. The user data directory is `~/Library/Application Support/Dia/User Data` (Arc: `…/Arc/User Data`), a normal Chromium profile tree (`Local State`, `Default/`, `History`, …).

### The ADK API

Dia's copy of the framework ships `Headers/` and `Modules/module.modulemap` (`framework module ArcCore`, umbrella `ArcCore.h`), so Swift imports it with `import ArcCore`. Arc's copy exports the same classes without headers or a module map. The resource bundle `ADK_ADK.bundle` in both apps suggests the toolkit's internal name is ADK.

The headers live under `arc/browser/objcpp/`: 201 Objective-C++ headers plus three `*.mojom-objc.h` Mojo bindings (`ai_service`, `arc_enterprise`, `arc_feature_list`). Every type is `NS_SWIFT_UI_ACTOR`, and the API is built on delegates and completion blocks. The main types:

| Type | Role |
|---|---|
| `ArcBrowserApplication` | Process-wide engine. `initialize:(ArcBrowserApplicationConfiguration*)`, `run`, `tryToTerminate:`, `createBrowser:withDelegate:forWindow:`, `createPopupBrowser:`, `restoreBrowser:withSessionID:…`, profile creation and loading, feature flags (`isFeatureEnabled:`/`setFeatureEnabled:`), import sources, accessibility switches, `showTaskManager`, `createAIService:` |
| `ArcBrowserApplicationConfiguration` | `argc`/`argv`, profile path, `ArcApplicationID` (Arc or Dia), production flag, session-restoration policy (`RestoreTabs` or `StartFresh`), whether to load every profile at start-up, the user-defaults suite |
| `ArcBrowserContext` (+ `…Autocomplete`, `…Downloads`, `…Extensions`, `…History`, `…Preferences`, `…DevTools`, `…PageContentExtraction`) | A Chromium profile and its services |
| `ArcBrowser` | One window's browser. The host gives it its `NSWindow` (`setWindow:`) and creates pages (`createWebContents:`). Also: cookies, omnibox autocomplete, extension toolbar actions (execute, pin, move, context menu), restoring closed and foreign tabs, close with `beforeunload` handling, side panel |
| `ArcWebContents` | One page. Navigation controller, back/forward list, find (including text-fragment directives), zoom, safe-area insets, stylesheet injection and removal, colour filters and schemes, JavaScript execution, viewport/full-page/region capture, print, save, PDF controller, media session and PiP, thumbnails, discard, `clone`, the accessibility tree with actions and `typeText:`, freezing votes, gesture handlers, top-band colour delegate, and an `aiAgent` and `boostIDE` per page |
| Delegates | `…NavigationDelegate`, `…UIDelegate`, `…ActionsDelegate`, `…GestureHandler`, `…TopBandColorDelegate`, `ArcBrowserDelegate`, `ArcBrowserApplicationDelegate` and so on: Chromium calls back into Swift for every piece of UI it would otherwise draw itself |
| Native UI models | `ArcMenuModel`, `ArcMenuItemModel` (context menus), `ArcPermissionRequest`, `ArcConfirmInfobar`, `ArcHungRendererDialog`, `ArcExternalProtocolDialog`, `ArcWebLoginDialog`, `ArcDevToolsConnectionDialog`: Chromium hands these to the host, and Swift presents them |
| AI in the engine (out of scope for Clair) | `ArcAIService`, `ArcAIInferenceModel`, `ArcAIDistilBertClassifier`, `ArcNomicEmbedTextModel`, `ArcCommandBarRanking*` (a learned ranking for command-bar results), `ArcContentConversionService`, `ArcExtractedPageContent`, and `ArcWebContents.aiAgent` |
| Diagnostics | `ArcTracingController`, `ArcNetworkActivityMonitor`, `ArcHistogramSamples`, `ArcMemoryDumpProvider`, `ArcCrashKeysReporter`, breadcrumb and dump-without-crashing callbacks |

So Chromium's `Browser` window, tab strip, omnibox, menus, infobars and dialogs are not on screen. The engine reports each of them as a model or a delegate call, and the Swift app draws its own version.

## Swift app

- **Modules:** 51 `BoostBrowser_*` feature bundles (for example `BoostCommandBar`, `ContentPane`, `NavigationBar`, `FloatingInput`, `DragDrop`, `GesturalNavigation`, `NewTabPage`, `SupertabEngine` and `SupertabFrontend`, `CleanTabs`, `Preferences`), alongside modules for the assistant that Clair sets aside. Dia keeps only 7 of Arc's 48 `ARC_*` feature modules: `AboutWindow`, `Emojis`, `PictureInPicture`, `SoftwareUpdaterClient`, `TopDomains`, `WebContentBehaviorConfigurationClient` and `WindowThemeUI`. It also shares the `ARCClients_*`, `ARCFoundation` and `ARCUI` base layers with Arc. In practice the UI was rewritten and the base layers were kept.
- **System frameworks linked by the main binary:** SwiftUI, WebKit, AVFoundation, Metal, NaturalLanguage, ScreenCaptureKit, CoreML, Vision and Speech. Arc links CloudKit instead of CoreML, Vision and Speech.
- **Third-party libraries:** GRDB, Lottie, Sentry, Sparkle, Datadog, LaunchDarkly (feature flags), SDWebImage, DomainParser, swift-crypto, ZIPFoundation, SwiftProtobuf, QRCode, Highlightr, SwiftMath and SwiftImageReadWrite. The on-device model libraries are listed under AI features.
- **Libraries Arc no longer ships in Dia:** Firebase/Firestore with gRPC, abseil, leveldb, nanopb and Promises (Arc's sync), GTMSessionFetcher, and YouTubePlayerKit.

## State and storage

| | Dia | Arc |
|---|---|---|
| Sidebar and tab model | `User Data/Default/tabs.db` (SQLite through GRDB, encrypted) | `StorableSidebar.json` and `StorableWindows.json` (plain JSON; see `look-and-behaviour.md`) |
| Other app state | Per profile in `User Data/Default/`: `assistant.db`, `agent_artifacts.db`, `custom_skills_database.db`, `skills_history_database.db`, `memory_key_value_store.db`, `key_value_store.db`, `live_data_database.db`, `mcp_auth.db`, `tool-result-snapshots.db`. Global in `User Data/`: `global_key_value_store.db`, `keyboard_shortcuts_database.db`, `tool_usage_store.db`, `sync_queue.db` | About 15 `Storable*.json` files beside `User Data/` (archive, auth state, command-bar ranking, link routing, live data, session restoration, …), with dated backup copies |
| Encryption | Dia's own databases have no plain SQLite header, and the binary references `sqlCipherHex`, so they are encrypted with SQLCipher. Chromium's `History` stays plain SQLite | Plain JSON |
| Sync | Its own queue in `sync_queue.db`; no CloudKit or Firebase in the bundle | Firebase Firestore with gRPC, plus CloudKit (`StorableFirebaseEncryptionKey.json`) |
| Placement | Inside Chromium's user data directory, beside each profile's own files | Beside `User Data/`, outside the Chromium tree |
| Outside `User Data/` | `BlockList.json`, `StorableAutoArchive.json`, `Favicons/`, `RemoteAssetDirectory/`, `AgentServer/` | `Storable*.json`, `StorableARCDocuments/` |

Entitlements match: Dia drops Arc's iCloud container, iCloud services and push (`aps-environment`) entitlements. Both keep associated domains, camera, microphone, location and `com.apple.developer.web-browser.public-key-credential` (system passkeys).

## AI features (out of scope for Clair)

Recorded only so these parts of the bundle can be recognised and set aside. Clair takes none of them.

- **What ships:** `Resources/agent-server-resources/` (409 MB) holds a Bun-compiled `agent-server`, a bundled Claude Code CLI, agent definitions, prompts and integration schemas. `libAIInfra.dylib`, `libContentConversion.dylib`, `AIInfra_*`, `mlx-swift`, `swift-transformers` and `OnDeviceLoRAadaptors` provide on-device models. About a dozen of the `BoostBrowser_*` modules and most of the per-profile databases (`assistant.db`, `agent_artifacts.db`, the skills, memory, tool and MCP stores) belong to the assistant.
- **How it runs:** the app starts one agent server per profile as a separate process under a Seatbelt profile that denies everything by default, and talks to it over a loopback TCP port. The AI work stays out of both the app process and Chromium.

## What Dia changed from Arc

| Area | Arc | Dia |
|---|---|---|
| Engine | `ArcCore.framework`, API not published in the bundle | The same framework and API, now with headers and a module map |
| Architectures | Universal | arm64 only, macOS 14 or later |
| UI modules | 48 `ARC_*` features | 51 `BoostBrowser_*` features on the shared `ARCClients`, `ARCFoundation` and `ARCUI` base |
| State | Plain JSON files | Encrypted SQLite through GRDB |
| Sync | Firebase plus CloudKit | Its own sync queue; no Firebase, CloudKit or push |
| AI (out of scope) | None beyond NaturalLanguage | On-device models and a sandboxed local agent server |

## Not established

- the purpose of the Aperitif helpers and `libaperitif.dylib`
- how much Dia's Chromium is patched, or how the engine is built and released
- which Swift module draws which part of the window
- the schemas inside Dia's encrypted databases
