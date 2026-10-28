# Lody iOS

- This is an independent iOS-only UIKit client. pnpm builds the bundled cloud protocol assets; XcodeGen and CocoaPods generate the native workspace.
- All first-party UI and capabilities live in `apps/mobile/modules/lody-kit`. Use Swift/UIKit or SwiftUI; do not add bridge packages. After adding or removing files under `modules/lody-kit/ios`, run `pnpm --filter @lody-ios/mobile pods`. CocoaPods snapshots the source glob; never edit `Pods.xcodeproj` by hand.
- Do not add Android implementations, fallback stubs, or Android build scripts.
- `apps/mobile/ios` is generated. Persist app configuration in `apps/mobile/native`, extension generators in `plugins/*.rb`, and features in LodyKit. Run `pnpm prebuild` then `pnpm --filter @lody-ios/mobile pods`.
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
- Do not use green as the app accent. Diff additions use systemGreen, paired with systemRed deletions. Use UIKit semantic colors for native content, system blue for actions, and neutral system backgrounds. Preserve automatic dark mode and accessibility contrast adaptation.
- Preserve native navigation, safe areas, VoiceOver labels, and at least 44 pt touch targets. MVP acceptance uses the default text size; keep system text behavior but do not add special layouts or remount logic for oversized accessibility text.
- Reference Yohaku iOS for native UI boundaries. System grouped rows use `LodyGroupedList` / `UICollectionViewListCell` in LodyKit; navigation uses UIKit automatic scroll edges through the existing native stack. Register native collection views with UIKit directly; do not simulate native effects with decorative overlays.

- Navigating native list rows retain selection until the owning controller returns. Deselect alongside the navigation transition and restore selection when an interactive return is cancelled; ordinary action rows deselect immediately. Diffable snapshots preserve selection themselves; never reselect a captured row in snapshot completion, which can run after return-time deselection.

## Pages and native APIs

- `LodyShell` owns the root navigation controller and sheet navigation controllers. `LodyPageController` hosts native content, carries results and clears callbacks on close. Reuse `pushNative`, `presentNative`, `finish` and `close`; do not add a second presentation manager.
- Deep links are parsed by `LodyCore.AppLink` and routed by `LodyApplication`. Notification navigation validates account, workspace and session catalog before opening a session.
- `HomeController` owns the adaptive UIKit split and list, session and inspector navigation controllers. Preserve system back and interactive pop. `SessionNavigation` handles session actions; tool pages use `LodyShell.presentDetail`. Keep sheets for transient flows and Debug demos.
- Register page factories in `Shell/LodyNativePages.swift`. Controllers read Swift-owned state and observe NotificationCenter changes. Inject service closures for I/O; offline preview subclasses use scripted services. Strings come from `LodyStrings.text`; add key prefixes to `NATIVE_PREFIXES` in `plugins/locales.js`.
- Pages write bar items to the hosting `LodyPageController.navigationItem`. Bottom toolbars appear only while their page is top; item updates wait for the running transition. Remove observers when their owner goes away; UIKit work runs on the main actor.
- `pnpm test` checks cloud protocol and verification tooling. Use Node 22 LTS (22.13+) for TypeScript stripping and module mocks. `pnpm verify:native` checks native behavior; `swift test --package-path packages/lody-core` checks routing and protocol policy.

- Keep fault injection, runtime internals, and navigation/native demos on the development-only Debug page, reached from Settings. Product screens expose actionable connection state only.

## Cloud POC

- Device Flow uses the currently registered `lody-cli` client transparently; do not claim a dedicated iOS client until the server registers one. Never substitute desktop credentials for app authorization.
- `data-runtime` in LodyKit owns the POC's catalog replicas, Streams reads, cursors and retry. Native sessions observe projected catalog events; do not add a second live replica. The old offline decoder is retained only as a comparison path.
- Swift owns the offscreen WebView and watchdog. Keep startup/heartbeat deadlines outside JS, ignore callbacks from replaced views, and bound automatic restarts. Background suspension is not a watchdog failure: retain the WebView and reset its heartbeat deadline on foreground; recreate only a missing or failed runtime. User-started sends use only a short UIApplication background allowance through reply synchronization; never request BGContinuedProcessingTask, which displays a system Live Activity, or use idle connection keepalive.
- The host↔runtime boundary is the versioned contract in `packages/cloud-runtime/src/contract`, with generated Swift in `packages/lody-core` (`pnpm contract`). Add methods there: the runtime exposes only `dataRuntime.receive` and posts only `ready` / `envelope`; do not add `callAsyncJavaScript` commands.
- Only short-lived workspace Streams grants enter the bundled WebView; long-lived Better Auth credentials stay in Keychain. Never load remote scripts or expose tokens in diagnostics. Logout and unsubscribe must stop the owned runtime.
- This POC reads catalogs and session history, and sends text turns. CRDT replicas restore from server bootstrap. App account/workspace context and complete catalog display projections restore from SQLite in LodyKit before background authentication and sync; credentials remain in Keychain. Loro/Flock updates use uint32 big-endian length frames; never append raw WASM exports. Persist the user history before the durable dispatch pointer and Machine RPC. A machine ACK is delivery, not completion. Never automatically replay writes across runtime recovery. Catalogs have an explicit 8 MiB per-replica input ceiling; do not label an incomplete or failed sync as live.
- Generate native runtime assets before prebuild/build. Preserve dependency licenses beside generated resources. Native watchdog behavior has a deterministic Swift check in `modules/lody-kit/verification/watchdog`.

- `ChatComposerView` in LodyKit owns the shared native input, draft handoff/restore, and model controls. Chat embeds it directly. The new-session form is native (`CreateSession/CreateSessionController`) and is shared by the app sheet (`LodyCreateSessionView`) and the Share Extension; it places the composer on the keyboard layout guide, so do not add a second keyboard avoidance owner. Build its pages from `LodyGroupedList` / `LodyPagedList`, and before changing it capture `verify:ui --case create-parity` from the previous build, then compare with `verification/ui/parity-diff.py`. New-session drafts carry text and attachments together into the first turn, including native restoration when upload fails.

## Share Extension

- `LodyShare` is generated by `plugins/share-extension.rb` and compiles listed LodyKit sources by reference, guarded by `LODY_SHARE_EXTENSION`. It never runs the WebView, data runtime or network, and never reads Keychain.
- The app writes a credential-free App Group snapshot (`ShareStore`: catalog, cached options, prefs). Send writes an inbox entry and opens `lody://share/<id>`; `NativeShareCoordinator` drains entries into the ordinary outbox, and falls back to the pre-filled form when the selection is unresolved or stale. The link only wakes the drain.

## UI regression verification

- UI Verify runs only in English (`en`, `en_US`), retaining light/dark coverage. Do not run a separate Chinese locale pass.
- UI Verify establishes the English software keyboard and offline environment once per runner batch; cases reuse that baseline. Enter Debug fixtures through `UI.open_case` deep links, never by scrolling the Debug menu. Batch text input; use individual software keys only when the key interaction is itself under test. Record entry/check timings and prefer observable readiness over fixed sleeps.
- On native UIKit pages use `axe drag`, not `swipe`; swipe doesn't drive UIKit pan gestures (switch thumbs, edge back).

- UI baselines must run without login, user credentials, cloud access, or a connected machine. Add independently resettable Debug scenes using production controllers and `LodyShell.presentNative`; inject deterministic data/service outcomes at their boundary.
- UI changes must add/update a behavior check in `apps/mobile/verification/ui` or reuse the existing native checks. Shared controls must be exercised in each affected host.
- Local checks omit `--udid` to lease a `Lody * Verify` Simulator. Build with `pnpm verify:build` (one shared Xcode DerivedData per checkout; never pass a per-task `-derivedDataPath` or copy the checkout into the temp directory, and reclaim such leftovers with `pnpm verify:clean`). Wrap build + multi-check flows with `pnpm verify:simulator --name '<current verify>' -- <command>` and use `$LODY_VERIFY_UDID`; never call `simctl create` directly. Explicit `--udid` is for caller-owned devices such as CI. See `apps/mobile/verification/ui/README.md`.
- Capture screenshots for visual states and video for temporal behavior. Missing scenes/timeouts fail verification; screenshots alone do not establish visual correctness.

## Push notifications

- Native OneSignal SDK ownership stays in LodyKit `Notifications/PushNotifications.swift`;
  `PushLifecycle` initializes at app launch, retains SDK listeners and caches
  clicks until `LodyApplication` resolves and acknowledges them.
- `native/Podfile`, `native/Lody` and `plugins/push-extension.rb` persist the NSE, App Group,
  SDK pin and entitlements across prebuild. Never fix only generated `ios/` files.
- Notification navigation accepts only the legacy workspace/session route and resolves
  against the signed-in user's catalog. `recipientUserId` fences clicks after an
  account switch; old payloads use the SDK's current external ID as a compatibility fallback.
- Debug's offline notification fixture never initializes OneSignal or requests real
  permission. See `apps/mobile/PUSH_NOTIFICATIONS.md` for setup and verification limits.
