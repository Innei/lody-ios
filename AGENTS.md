# Lody iOS

- This repository holds the independent UIKit iOS client and the AppKit Mac client (`macOS/`, `packages/LodyMacKit`, product “Lody”, bundle id `app.innei.lody.mac`). pnpm builds the bundled cloud protocol assets; XcodeGen generates app, extension and verification targets; Swift Package Manager builds LodyiOSKit and its native dependencies.
- Platform-neutral data (auth, catalog, outbox, data runtime, local store, session sources and senders, create-session data, transcript projection, the string catalog) lives in `packages/LodyData`, which imports only Foundation and builds for iOS and macOS. It never imports UIKit or AppKit; platform effects go through the `LodyHost` seam (`LodyHosting.current`), which LodyiOSKit implements as `LodyUIKitHost`. LodyiOSKit re-exports LodyData. Live wiring that reads Debug fixtures or list rows stays in LodyiOSKit as extensions (`SessionSource.live`, `CreateSessionService.live`).
- First-party UI lives in the Swift package `packages/LodyiOSKit/Sources`; the iOS application entry point is `iOS`, and extensions are in `Extensions`. Use Swift/UIKit or SwiftUI; do not add bridge packages. SwiftPM discovers LodyiOSKit sources automatically. Run `pnpm prebuild` after changing app/extension source membership or shared extension references in `project.yml`; never edit the generated Xcode project by hand.
- Do not add Android implementations, fallback stubs, or Android build scripts.
- `Lody.xcodeproj`, `.generated` are generated. Persist app configuration in `iOS`, app/extension target definitions in `project.yml`, and package dependencies/resources in `packages/LodyiOSKit/Package.swift` and `packages/LodyData/Package.swift`. Run `pnpm prebuild`.
- Keep normal Xcode signing enabled, including simulator validation. Do not use `CODE_SIGNING_ALLOWED=NO`.
- Cloud integration targets official Lody Cloud. Use browser-safe public protocol imports in `packages/cloud-runtime`; do not import Node-dependent `@lody/shared` or `@lody/loro-streams-rpc` root entries, absolute paths from another checkout, or private backend packages.
- Credentials belong in Keychain. Never copy desktop credentials, tokens, transcripts, or private service configuration into this repository.
- `LodyApplication` owns lifecycle and application coordinators. `AuthSession`, `CatalogSession` and `OutboxSession` own native state; feature controllers observe their projections. Keep protocol code in `packages/cloud-runtime` and generated wire types in `packages/lody-core` (`pnpm contract`).
- Shell pages use transparent headers and soft scroll edges. Native pages bind their scroll view through `LodyScrollEdges`.
- Preserve user edits. Before destructive revert/restore/rollback, inspect the working tree and obtain explicit confirmation.
- Verify with `pnpm check`, `pnpm bundle`, and an iOS simulator build when changing native code. Prefer behavioral checks over implementation snapshots.
- Do not nest ternary expressions. One `cond ? a : b` is fine; a `?` inside either branch is not. Map a closed set with a dictionary, and use `if` / `switch` for ordered or overlapping conditions. Optional chaining and `??` are not ternaries.

## UI baseline

- Apple HIG is the primary UI requirement. Chat references inform behavior only; preserve native conventions.
- Do not use green as the app accent. Diff additions use systemGreen, paired with systemRed deletions. Use UIKit semantic colors for native content and neutral system backgrounds. The default accent is Lody (`lodySignal`, the icon's indigo); actions follow the accent, and chat links stay systemBlue. Signal colors are fixed on status glyphs (live arc, unread dot) and on live tentacle tree lines; teal (`lodySignalTail`) appears only as a gradient end. Preserve automatic dark mode and accessibility contrast adaptation.
- Preserve native navigation, safe areas, VoiceOver labels, and at least 44 pt touch targets. The chat transcript is the one exception: stacked full-width rows (process, summary and sub-agent rows at 30 / 40 pt, file rows at 40 pt, the file summary at 42 pt, the meta row at 32 pt) may be shorter. MVP acceptance uses the default text size; keep system text behavior but do not add special layouts or remount logic for oversized accessibility text.
- Reference Yohaku iOS for native UI boundaries. System grouped rows use `LodyGroupedList` / `UICollectionViewListCell` in LodyiOSKit; navigation uses UIKit automatic scroll edges through the existing native stack. Register native collection views with UIKit directly; do not simulate native effects with decorative overlays.
- `LodyGroupedList` system-row pages default to flat rail rows; CreateSession and its pickers opt back into inset-grouped rows with `setGrouped(true)`.
- Home section heads are `lodyBand` bands: full-bleed and square on iPhone; in the iPad sidebar they are inset with 12 pt side margins and rounded corners, because full-bleed bands clash with the inset sidebar rows.
- Chat process, summary and sub-agent rows use Home's rail glyphs and tentacle tree lines; answer text uses the full width with 16 pt margins. A turn divider (hairlines and the turn's time) precedes each new run, not steers. File changes form one grouped `lodyInset` block that is collapsed to a summary row when it has more than one file, and code blocks use `lodyInset` fill. The composer is outside the design language rail scope.

- Navigating native list rows retain selection until the owning controller returns. Deselect alongside the navigation transition and restore selection when an interactive return is cancelled; ordinary action rows deselect immediately. Diffable snapshots preserve selection themselves; never reselect a captured row in snapshot completion, which can run after return-time deselection.

## Pages and native APIs

- `LodyShell` owns the root navigation controller and sheet navigation controllers. `LodyPageController` hosts native content, carries results and clears callbacks on close. Reuse `pushNative`, `presentNative`, `finish` and `close`; do not add a second presentation manager.
- Deep links are parsed by `LodyCore.AppLink` and routed by `LodyApplication`. Notification navigation validates account, workspace and session catalog before opening a session.
- `HomeController` owns the adaptive UIKit split and list, session and inspector navigation controllers. Preserve system back and interactive pop. `SessionNavigation` handles session actions; tool pages use `LodyShell.presentDetail`. Keep sheets for transient flows and Debug demos.
- Register page factories in `Shell/LodyNativePages.swift`. Controllers read Swift-owned state and observe NotificationCenter changes. Inject service closures for I/O; offline preview subclasses use scripted services. Use `String(localized:bundle:)` with `.lody` and edit `packages/LodyData/Sources/Resources/Localizable.xcstrings` directly (one catalog shared by LodyData and LodyiOSKit; LodyData code uses `.lodyData`). Use Foundation format arguments and catalog plural variations; `InfoPlist.xcstrings` owns permission prompts.
- Pages write bar items to the hosting `LodyPageController.navigationItem`. Bottom toolbars appear only while their page is top; item updates wait for the running transition. Remove observers when their owner goes away; UIKit work runs on the main actor.
- `LodyFormController` editors use inline-label `LodyFormRow` rows in hairline-separated `LodyFormGroup` groups on `lodyGround`.
- `pnpm test` checks cloud protocol and verification tooling. Use Node 22 LTS (22.13+) for TypeScript stripping and module mocks. `pnpm verify:native` checks native behavior; `swift test --package-path packages/lody-core` checks routing and protocol policy.

- Keep fault injection, runtime internals, and navigation/native demos on the development-only Debug page, reached from Settings. Product screens expose actionable connection state only.

## Cloud POC

- Device Flow uses the currently registered `lody-cli` client transparently; do not claim a dedicated iOS client until the server registers one. Never substitute desktop credentials for app authorization.
- `data-runtime` in LodyData owns the POC's catalog replicas, Streams reads, cursors and retry. Native sessions observe projected catalog events; do not add a second live replica. The old offline decoder is retained only as a comparison path.
- Swift owns the offscreen WebView and watchdog. Keep startup/heartbeat deadlines outside JS, ignore callbacks from replaced views, and bound automatic restarts. Background suspension is not a watchdog failure: retain the WebView and reset its heartbeat deadline on foreground; recreate only a missing or failed runtime. User-started sends use only a short UIApplication background allowance through reply synchronization; never request BGContinuedProcessingTask, which displays a system Live Activity, or use idle connection keepalive.
- The host↔runtime boundary is the versioned contract in `packages/cloud-runtime/src/contract`, with generated Swift in `packages/lody-core` (`pnpm contract`). Add methods there: the runtime exposes only `dataRuntime.receive` and posts only `ready` / `envelope`; do not add `callAsyncJavaScript` commands.
- Only short-lived workspace Streams grants enter the bundled WebView; long-lived Better Auth credentials stay in Keychain. Never load remote scripts or expose tokens in diagnostics. Logout and unsubscribe must stop the owned runtime.
- This POC reads catalogs and session history, and sends text turns. CRDT replicas restore from server bootstrap. App account/workspace context and complete catalog display projections restore from SQLite in LodyData before background authentication and sync; credentials remain in Keychain. Loro/Flock updates use uint32 big-endian length frames; never append raw WASM exports. Persist the user history before the durable dispatch pointer and Machine RPC. A machine ACK is delivery, not completion. Never automatically replay writes across runtime recovery. Catalogs have an explicit 8 MiB per-replica input ceiling; do not label an incomplete or failed sync as live.
- Generate native runtime assets before prebuild/build. Preserve dependency licenses beside generated resources. Native watchdog behavior has a deterministic Swift check in `verification/kit/watchdog`.

- `ChatComposerView` in LodyiOSKit owns the shared native input, draft handoff/restore, and model controls. Chat embeds it directly. The new-session form is native (`CreateSession/CreateSessionController`) and is shared by the app sheet (`LodyCreateSessionView`) and the Share Extension; it places the composer on the keyboard layout guide, so do not add a second keyboard avoidance owner. Build its pages from `LodyGroupedList` / `LodyPagedList`, and before changing it capture `verify:ui --case create-parity` from the previous build, then compare with `verification/ui/parity-diff.py`. New-session drafts carry text and attachments together into the first turn, including native restoration when upload fails.

## Mac client

- The Mac app is a cloud client only. `LodyMacKit` owns AppKit UI and implements `LodyHost` as `MacHost`: the runtime never suspends when Lody is not frontmost, and closing the last window keeps it syncing. It never registers `lody://`, which the official desktop app owns.
- Mac storage lives under `~/Library/Application Support/app.innei.lody.mac` (`LodyStorage.root`); never write to the shared `Lody` folder the official desktop app uses. Credentials stay in this Mac's Keychain.
- Mac UI strings live in `packages/LodyMacKit/Sources/Resources/Localizable.xcstrings` (`bundle: .lodyMac`); `pnpm i18n:check` covers them.
- Debug builds register `lodymacverify://` only: `case/<name>` opens an offline UI catalog scene built from production controllers, plus `reset`, `appearance/light|dark` and `dump?out=<absolute .json>` (in-process view state); `--ui-verify-open <url>` applies the same routes at launch. The Debug page is in the app menu and Settings.
- Build with `pnpm mac:build`. Mac UI verification never touches the host's screen, pointer or keyboard: never run XCUITest, auv or a windowed VM on the host.
- Everyday checks: `pnpm verify:mac [--case <name>]` drives controls in-process and asserts on view dumps; `--ui-verify-offscreen` keeps every window beyond all displays and out of the Dock.
- Final gate before a Mac feature is done: `pnpm verify:mac:vm [--case <name>] [--in-process]` builds for testing on the host, then runs the `LodyMacUITests` XCUITest target (real clicks, menus and typing, light and dark screenshots) in the warm headless runner VM `lody-verify-runner` (a Tart clone of a macOS 27.2 guest) and exports screenshots to `.artifacts/mac-verify-vm`. Runs take turns on one lock; each resets Lody's processes and state in the guest, and the runner stops after 30 idle minutes. It is re-cloned only when the base changes, after an infrastructure failure (boot, SSH, no result bundle, timeout; failing tests never count), or on `pnpm verify:mac:vm reset`; `--fresh` uses a disposable clone instead. UI tests launch the app once per class with launch routes and switch scenes and appearance through the Debug app's distributed-notification inbox (`MacVerifyInbox`), never `XCUIApplication.open`. The runner's `VNC:` URL (also in `vnc.txt`) is the guest's Screen Sharing on loopback port 5905 or the next free one (`--vnc-port <n>`) while it is up; `pnpm verify:mac:vm watch` starts the runner if needed and opens it in Screen Sharing already logged in (`--print-only` prints the URL); use View → Observe so your input never reaches the run, and pass `--hold` to keep the run's lock until Ctrl-C. Runs fail if anything they start listens off loopback. `pnpm verify:mac:vm prepare --recovery-vnc` builds or updates the base VM (local Xcode copy with the iOS Simulator runtime and first launches done, SIP off, trimmed services) in the APFS sparse bundle `/Volumes/WD/lody-vm.sparsebundle`; only that flag allows the recovery boot's LAN-reachable VNC server. Each run verifies the guest Xcode's signatures; on failure run `prepare --repair-xcode`, and `--host-xcode` is the shared-Xcode fallback.

## Share Extension

- `LodyShare` is declared in `project.yml` and compiles listed LodyiOSKit sources by reference, guarded by `LODY_SHARE_EXTENSION`. It never runs the WebView, data runtime or network, and never reads Keychain.
- The app writes a credential-free App Group snapshot (`ShareStore`: catalog, cached options, prefs). Send writes an inbox entry and opens `lody://share/<id>`; `NativeShareCoordinator` drains entries into the ordinary outbox, and falls back to the pre-filled form when the selection is unresolved or stale. The link only wakes the drain.

## UI regression verification

- UI Verify runs only in English (`en`, `en_US`), retaining light/dark coverage. Do not run a separate Chinese locale pass.
- UI Verify establishes the English software keyboard and offline environment once per runner batch; cases reuse that baseline. Enter Debug fixtures through `UI.open_case` deep links, never by scrolling the Debug menu. Batch text input; use individual software keys only when the key interaction is itself under test. Record entry/check timings and prefer observable readiness over fixed sleeps.
- On native UIKit pages use `axe drag`, not `swipe`; swipe doesn't drive UIKit pan gestures (switch thumbs, edge back).

- UI baselines must run without login, user credentials, cloud access, or a connected machine. Add independently resettable Debug scenes using production controllers and `LodyShell.presentNative`; inject deterministic data/service outcomes at their boundary.
- UI changes must add/update a behavior check in `verification/ui` or reuse the existing native checks. Shared controls must be exercised in each affected host.
- Local checks omit `--udid` to lease a `Lody * Verify` Simulator. Build with `pnpm verify:build` (one shared Xcode DerivedData per checkout; never pass a per-task `-derivedDataPath` or copy the checkout into the temp directory, and reclaim such leftovers with `pnpm verify:clean`). Wrap build + multi-check flows with `pnpm verify:simulator --name '<current verify>' -- <command>` and use `$LODY_VERIFY_UDID`; never call `simctl create` directly. Explicit `--udid` is for caller-owned devices such as CI. See `verification/ui/README.md`.
- Capture screenshots for visual states and video for temporal behavior. Missing scenes/timeouts fail verification; screenshots alone do not establish visual correctness.

## Push notifications

- Native OneSignal SDK ownership stays in LodyiOSKit `Notifications/PushNotifications.swift`;
  `PushLifecycle` initializes at app launch, retains SDK listeners and caches
  clicks until `LodyApplication` resolves and acknowledges them.
- `project.yml` and `iOS` persist the NSE, App Group,
  SDK pin and entitlements across prebuild. Never fix only generated `ios/` files.
- Notification navigation accepts only the legacy workspace/session route and resolves
  against the signed-in user's catalog. `recipientUserId` fences clicks after an
  account switch; old payloads use the SDK's current external ID as a compatibility fallback.
- Debug's offline notification fixture never initializes OneSignal or requests real
  permission. See `PUSH_NOTIFICATIONS.md` for setup and verification limits.
