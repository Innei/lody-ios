# Live Activity implementation plan

Spec: `docs/superpowers/specs/2026-09-09-live-activity-design.md` (binding authority).
Branch: `feat/live-activity`. Work in `/Users/innei/git/innei-repo/lody-ios`.

## Global Constraints

- Follow `CLAUDE.md` and `apps/mobile/CLAUDE.md`. Zero comments and zero JSDoc unless
  documenting an unexpected workaround. No nested ternaries. Files under 500 lines,
  React components under 300.
- LodyKit compiles as Swift 6 with strict concurrency; UI and ActivityKit work is
  `@MainActor`. Follow the `PushNotifications` pattern: `@MainActor final class`
  singleton, `nonisolated` callbacks hopping to main with `Task { @MainActor in }`,
  module `AsyncFunction` bodies wrapped in `MainActor.assumeIsolated` on
  `.runOnQueue(.main)`.
- Never pass `CODE_SIGNING_ALLOWED=NO`. Simulator builds keep automatic signing with
  team `KAMM5N88X3`.
- `pnpm` on this machine is broken. Prepend
  `/private/tmp/claude-501/-Users-innei-git-innei-repo-lody-ios/ccfa6190-9b4e-49f8-8de3-15f8e8c22569/scratchpad/bin`
  to `PATH` (it holds a `pnpm` shim to `corepack pnpm@11.10.0`), or call
  `node_modules/.bin/expo` and `node scripts/...` directly from `apps/mobile`.
  Prebuild is `node scripts/build-decoder.mjs && ../../node_modules/.bin/expo prebuild --platform ios --no-install`
  from `apps/mobile`; pods is `cd ios && PATH="$(brew --prefix ruby)/bin:$PATH" bundle exec pod install`.
- Simulator build command (from `apps/mobile`):
  `xcodebuild -workspace ios/Lody.xcworkspace -scheme Lody -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build`.
- Verification harness: `python3 apps/mobile/verification/simulator.py --name '<name>' -- <cmd>`
  leases a `Lody * Verify` Simulator and exports `LODY_VERIFY_UDID`. Never call
  `simctl create` directly. Use a fresh `--output` directory per `verify:ui` run.
- Identifiers (already registered in the Apple Developer portal):
  - main app `app.innei.lody`, App Group `group.app.innei.lody`
  - notification service extension `app.innei.lody.notification-service`
  - widget extension `app.innei.lody.live-activity`
- Activity id format: `lody-conversations:v5:{workspaceId}:{userId}`.
- Deep link route: `lody:///{workspaceSlug}/sessions/{sessionId}`.
- Colors in the widget: `Color.blue` running, `Color.orange` needs-you (permission and
  question), `Color.green` completed. No brand imagery; agent glyph is the two-letter
  `agentLogoText` on a neutral rounded square.
- Commit each task with a conventional message ending in
  `Claude-Session: https://claude.ai/code/session_01XUtB8iFfppLAGx7rSY9s57`. Never push.

## Task 1: Scheme, widget extension target, and build plumbing

Files:

- `apps/mobile/app.config.ts`
- `apps/mobile/plugins/push-extension.rb`
- `apps/mobile/plugins/withPushNotifications.js`
- `apps/mobile/modules/lody-kit/live-activity/LodyLiveActivityWidget.swift` (placeholder)
- `apps/mobile/PUSH_NOTIFICATIONS.md`

Steps:

1. Change `scheme` in `app.config.ts` from `'lody-ios'` to `'lody'`.
2. Generalize `push-extension.rb`: extract the target-building logic into
   `lody_extension(bundle_id, name:, suffix:, source_dir:, point_identifier:, principal_class:, product_type:)`
   so `lody_push_extension(bundle_id)` becomes a thin call for the existing NSE, and add
   `lody_live_activity_extension(bundle_id)` that builds target `LodyLiveActivity`:
   - product type `com.apple.product-type.app-extension`, `NSExtensionPointIdentifier`
     `com.apple.widgetkit-extension`, no principal class key (WidgetKit uses `@main`).
   - `PRODUCT_BUNDLE_IDENTIFIER` `#{bundle_id}.live-activity`.
   - entitlements: `com.apple.security.application-groups` = `["group.#{bundle_id}"]`.
   - copies every `*.swift` from `modules/lody-kit/live-activity/` into `ios/LodyLiveActivity/`
     and adds them to the target's source phase (idempotent on rerun).
   - build settings: `SWIFT_VERSION` `6.0`, `IPHONEOS_DEPLOYMENT_TARGET` from the app,
     `TARGETED_DEVICE_FAMILY` `1`, `SKIP_INSTALL` `YES`, `GENERATE_INFOPLIST_FILE` `NO`,
     `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` copied like the NSE, `DEVELOPMENT_TEAM`
     from the app, `CODE_SIGN_STYLE` `Automatic`.
   - embeds the `.appex` in the app's existing `Embed App Extensions` phase.
   - The extension's `Info.plist` must include `NSSupportsLiveActivities` is NOT needed
     (that goes in the app plist); include `CFBundleDisplayName` `Lody`.
3. In `withPushNotifications.js`:
   - add `NSSupportsLiveActivities: true` and `NSSupportsLiveActivitiesFrequentUpdates: false`
     to the app Info.plist;
   - the Podfile marker block also calls `lody_live_activity_extension('<bundle>')` and
     declares `target 'LodyLiveActivity' do pod 'OneSignalXCFramework/OneSignalLiveActivities', '5.5.1' end`
     only if that subspec exists in the pinned SDK (check `ios/Pods` after a first
     install; if the subspec name differs, use the one that ships
     `OneSignalLiveActivities.xcframework`). The widget itself does not need OneSignal;
     if linking it into the widget causes trouble, leave the widget target pod-free
     and note it in the report.
4. Placeholder `LodyLiveActivityWidget.swift`: a `@main struct LodyLiveActivityBundle: WidgetBundle`
   with an empty `ActivityConfiguration` for a temporary
   `struct PlaceholderAttributes: ActivityAttributes { struct ContentState: Codable, Hashable {} }`
   so the target compiles. Task 3 replaces it.
5. Update `PUSH_NOTIFICATIONS.md` identifiers list with the widget bundle id.
6. Prebuild, pod install, simulator build. Confirm `Lody.app/PlugIns/LodyLiveActivity.appex`
   exists with `PRODUCT_BUNDLE_IDENTIFIER = app.innei.lody.live-activity`, the app plist
   has `NSSupportsLiveActivities`, and `CFBundleURLSchemes` contains `lody`.
7. `tsc --noEmit`, prettier on touched files, `node scripts/build-licenses.mjs --check`.

Test: the build succeeds and the four checks in step 6 hold (paste the grep output in
the report).

## Task 2: Shared activity contract and deterministic Swift check

Files:

- `apps/mobile/modules/lody-kit/live-activity/LodyActivityAttributes.swift`
- `apps/mobile/modules/lody-kit/verification/live-activity/main.swift`
- `apps/mobile/verification/native.py` (add `'live-activity': ['../live-activity/LodyActivityAttributes.swift']`
  or whatever relative form the harness needs; read how `checks` paths resolve first)

Contract (exact names, all `Codable`, `Hashable`, `Sendable`):

```swift
import ActivityKit

struct LodyActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable, Sendable {
    struct Counts: Codable, Hashable, Sendable { var permission = 0; var question = 0; var running = 0; var unread = 0 }
    struct Item: Codable, Hashable, Sendable {
      enum Status: String, Codable, Sendable { case permission, question, running, unread }
      var id: String
      var status: Status
      var statusLabel: String
      var permissionRequestId: String?
      var permissionCommand: String?
      var agentLogoKind: String
      var agentLogoText: String
      var title: String
      var updatedAt: Double
      var updatedAtLabel: String
    }
    struct PermissionAlert: Codable, Hashable, Sendable { var title: String; var body: String }
    var totalCount: Int
    var statusCounts: Counts
    var items: [Item]
    var permissionAlert: PermissionAlert?
  }
  var workspaceId: String
  var workspaceName: String
  var userId: String
}
```

Decoding must tolerate: missing `permissionAlert`, missing optional item fields,
unknown extra keys, `updatedAt` arriving as an integer, `statusCounts` missing a key
(defaults to 0), and `agentLogoKind` values outside the known set (kept as string).
Use a custom `init(from:)` only where `Codable` synthesis cannot give that tolerance.

Pure functions on `ContentState`:

- `var focus: Item?`: priority `question` > `permission` > `running` > `unread`; ties by
  larger `updatedAt`; nil when `items` is empty.
- `var others: [Item]`: items minus focus, same ordering rule, capped at 2.
- `var othersCount: Int`: `max(totalCount - 1, 0)` when focus exists, else 0.
- `var needsAttention: Bool`: focus status is `question` or `permission`.
- `var isActive: Bool`: `statusCounts.running + permission + question > 0`.
- `func staleDate(from updatedAt: Date) -> Date`: `updatedAt + 30 * 60`.
- `func dismissalDate(from updatedAt: Date) -> Date?`: `updatedAt + 15 * 60` when
  `!isActive && focus != nil`, else nil.
- `var focusRoute: String?` and `func route(for item: Item) -> String`: not here;
  routes need the workspace slug which the widget gets from `LodyActivityAttributes`.
  Instead add `static func route(workspaceSlug: String, sessionId: String) -> URL`
  producing `lody:///{workspaceSlug}/sessions/{sessionId}` with percent-encoding of
  both segments (`urlPathAllowed` minus `/`).

Note: the upstream payload carries `workspaceId` (an id), not the slug the app route
uses. Add `var workspaceSlug: String` to `LodyActivityAttributes` as well; Task 4
fills it from the catalog projection.

Verification `main.swift` (mirrors `verification/notifications/main.swift` style:
plain `precondition`s and a final `print("PASS: ...")`):

- decode a sample JSON with all fields, one with only required fields, one with
  integer `updatedAt` and an unknown top-level key;
- focus priority and tie-break;
- `others` cap at 2 and exclusion of focus;
- `isActive`, `dismissalDate` nil vs non-nil, `staleDate`;
- `route(workspaceSlug:sessionId:)` encoding of a slug containing a space.

Run it through `python3 apps/mobile/verification/native.py` on a leased simulator
(see Global Constraints) and paste the PASS line.

## Task 3: Widget UI

Files:

- `apps/mobile/modules/lody-kit/live-activity/LodyLiveActivityWidget.swift` (replace placeholder)
- `apps/mobile/modules/lody-kit/live-activity/LiveActivityViews.swift`
  (compact, minimal, expanded, lock screen views; split into a second file if it passes
  300 lines)

Requirements (spec "Presentation"):

- `ActivityConfiguration(for: LodyActivityAttributes.self)`.
- Lock screen / StandBy content: focus row only: glyph (34 pt rounded square,
  `Color.secondary.opacity(0.2)` fill, `agentLogoText` in `.caption.weight(.semibold)`),
  title (`.headline`, one line), status line (status symbol + `statusLabel` + when
  `othersCount > 0` the suffix "还有 N 个在跑"), trailing: running →
  `Text(timerInterval: updatedAt...distantFuture, countsDown: false)` in
  `.title2.monospacedDigit()` tinted blue; otherwise a capsule "查看" (orange for
  needs-attention, secondary otherwise). Whole row is `widgetURL` to the focus route.
  Empty `items` renders a single "没有活跃会话" line.
- Dynamic Island:
  - compact leading: glyph 20 pt; compact trailing: symbol only (running: a
    `ProgressView().progressViewStyle(.circular).tint(.blue)`; needs-attention: orange
    filled circle 10 pt; unread: `checkmark` SF Symbol green).
  - minimal: the trailing symbol.
  - expanded: `.leading` glyph 34 pt, `.center` title + status line, `.trailing` timer
    or "查看" pill, `.bottom`: when focus is permission with `permissionCommand`, a
    monospaced strip (`.caption.monospaced()`, secondary background, one line
    truncated); then a hairline and `others` rows (glyph 20 pt, title, status symbol),
    each wrapped in `Link(destination:)` to its route. No allow / reject buttons.
- Stale (`context.isStale`): grey out the content and replace the status line with
  "已断开".
- All strings are Chinese literals as in this task (the app's existing native code uses
  `LodyStrings`; the widget target does not include it, so keep literals here and note
  it in the report).
- Build the widget target in the simulator build. Xcode previews are optional.

Test: simulator build succeeds; add a `#Preview` for each of the four states is
optional. The deterministic behavior is covered by Task 2; screenshots come in Task 6.

## Task 4: LodyKit owner and module surface

Files:

- `apps/mobile/modules/lody-kit/ios/Notifications/LiveActivities.swift`
- `apps/mobile/modules/lody-kit/ios/LodyKitModule.swift`
- `apps/mobile/modules/lody-kit/ios/Cloud/DataRuntime.swift` (only if a hook is needed)
- `apps/mobile/modules/lody-kit/ios/LodyKit.podspec` (add the `OneSignalLiveActivities`
  subspec dependency if it is separate from `OneSignalXCFramework/OneSignal`; verify in
  `ios/Pods`)
- `apps/mobile/modules/lody-kit/src/notifications/notifications.ts` and
  `apps/mobile/modules/lody-kit/src/index.ts`
- `apps/mobile/modules/lody-kit/verification/live-activity/main.swift` (extend)

`LiveActivities` (`@MainActor final class`, `static let shared`):

- `var enabled: Bool` backed by `UserDefaults(suiteName: "group.app.innei.lody")` key
  `liveActivitiesEnabled`, default `true`.
- `func start()` called from `PushAppDelegateSubscriber.application(_:didFinishLaunchingWithOptions:)`
  after `PushNotifications.shared.start`: when `ActivityAuthorizationInfo().areActivitiesEnabled`,
  call `OneSignal.LiveActivities.setup(LodyActivityAttributes.self)` if the SDK exposes
  a generic setup for custom attributes; otherwise observe
  `Activity<LodyActivityAttributes>.pushToStartTokenUpdates` and forward through
  `OneSignal.LiveActivities.setPushToStartToken(activityType:withToken:)`, and observe
  each activity's `pushTokenUpdates` forwarding through `OneSignal.LiveActivities.enter(activityId, withToken:)`.
  Read the SDK headers under `ios/Pods/OneSignalXCFramework` to pick the real API; do
  not guess names.
- `func sync(catalogJSON: String, workspaceId: String, workspaceSlug: String, workspaceName: String, userId: String)`:
  parse only `sessions[].{id,title,status,awaitingUserSince,lastMessageAt,lastReadAt,agentType,cliType}`
  from the catalog JSON (the same shape as `src/models/catalog.ts`). Build an initial
  `ContentState` using: `awaitingUserSince != nil` → `permission`; status in
  `running, processing, in_progress, queued, pending` → `running`; else skipped.
  `statusLabel` values: permission "需要你授权", running "正在工作". `agentLogoText`:
  `codex` → "CX", `claude` → "CC", otherwise first two letters of `agentType` uppercased
  or "AC". If `enabled`, `isActive`, and no activity with this id exists, call
  `Activity.request(attributes:content:pushType: .token)` with the id in
  `attributes` and `staleDate` from the contract. If an activity exists, do nothing
  (server pushes own the content). If `!isActive` and an activity exists, leave it
  (server `ended` push or dismissal policy handles it).
- `func endAll(reason:)`: `end(nil, dismissalPolicy: .immediate)` on every
  `Activity<LodyActivityAttributes>.activities`, and `OneSignal.LiveActivities.exit(id)`
  for each. Called on logout (`clearAuthToken`) and when `enabled` turns false.
- `func status() -> [String: any Sendable]`: `{ enabled, supported: areActivitiesEnabled, active: activities.count }`.
- Hook: in `DataRuntime.publish` when `reason == "catalog"`, after the existing emit,
  call `LiveActivities.shared.sync(...)` with the workspace fields DataRuntime already
  holds (`start(workspace:owner:userId:)` gives workspace and userId; workspace slug and
  name: check what `workspace` is (slug or id) and read `LocalStore` for the display
  name; if the slug is not available in Swift, add it to `start(...)` and to the RN
  caller in `modules/lody-kit/src`). Keep `DataRuntime` changes to the minimum.
- `#if DEBUG` `func debug(_ action: String)` with actions `start-running`,
  `update-permission`, `end` that request / update / end a fixture activity
  (attributes workspace `debug`, slug `debug`, userId `debug`) using a fixed
  `ContentState` with three items (running focus "重构 composer 键盘避让" CC, one
  running "修复 push-extension 签名" CX, one unread "写 Live Activity 设计文档" CC);
  `update-permission` switches the CX item to `permission` with
  `permissionCommand` `git push origin main --force` and a `permissionAlert`, applied
  with `AlertConfiguration`. Never touches OneSignal.

Module surface (`LodyKitModule`, all `.runOnQueue(.main)` + `MainActor.assumeIsolated`):

- `AsyncFunction("liveActivityStatus")` → status dict.
- `AsyncFunction("setLiveActivitiesEnabled") { (enabled: Bool) in ... }`.
- `AsyncFunction("debugLiveActivity") { (action: String) in ... }` under `#if DEBUG`.
- `clearAuthToken` also calls `LiveActivities.shared.endAll(reason: "logout")`.

TS facade in `notifications.ts`: `liveActivityStatus(): Promise<LiveActivityStatus>`,
`setLiveActivitiesEnabled(enabled: boolean): Promise<void>`,
`debugLiveActivity(action: 'start-running' | 'update-permission' | 'end'): Promise<void>`,
`type LiveActivityStatus = { enabled: boolean; supported: boolean; active: number }`.
Export from `index.ts`.

Tests:

- extend `verification/live-activity/main.swift` with the catalog-to-ContentState
  mapping (put the mapping in `LodyActivityAttributes.swift` or a sibling
  `LiveActivityCatalog.swift` compiled by the check, so it has no ActivityKit
  dependency): a running session, an awaiting session, an idle session (skipped),
  agent glyph mapping.
- simulator build green; `tsc --noEmit` green.

## Task 5: React Native settings toggle, deep links, and tests

Files:

- `apps/mobile/src/screens/NotificationSettingsScreen.tsx`
- `apps/mobile/src/features/notifications/PushCoordinator.tsx`
- `apps/mobile/src/features/notifications/routing.ts` (only if a helper is needed)
- `apps/mobile/tests/notifications.test.mjs`
- `apps/mobile/locales/en.json`, `apps/mobile/locales/zh-Hans.json` (follow the
  existing i18n pattern in the settings screen; run `node apps/mobile/scripts/check-locales.mjs`)

Requirements:

- Settings: a "灵动岛" row with a native switch under the notification permission row.
  Reads `liveActivityStatus()`; disabled with subtitle "此设备不支持" when
  `supported === false`; toggling calls `setLiveActivitiesEnabled`. Keep the
  `NotificationService` injection pattern so the Debug preview can inject outcomes
  (extend the service type with `liveActivity: { status, setEnabled }`).
- Deep links: in `PushCoordinator`, subscribe to `Linking` (`getInitialURL` +
  `addEventListener('url')`). For URLs with scheme `lody`, take `pathname` and feed it
  through the same destination resolution used for push clicks
  (`parseNotificationRoute` + `resolvePushDestination`), with the current user as the
  recipient. Ignore other schemes. Unsubscribe on unmount.
- Tests in `notifications.test.mjs`: the URL-to-route extraction (`lody:///ws/sessions/s1`
  → `/ws/sessions/s1`; `lody://ws/sessions/s1` (host form) → same; percent-encoded
  slug decodes; foreign scheme ignored). Put the pure function in `routing.ts` as
  `routeFromDeepLink(url: string): string | null` so the test needs no RN mocks.
- Run the Node test suite for the touched files and `tsc --noEmit`, prettier on
  touched files, locale check.

## Task 6: Debug scene and UI verification

Files:

- `apps/mobile/src/screens/debug/NotificationPreviewScreen.tsx` (extend) or a new
  `LiveActivityPreviewScreen.tsx` if the existing one would pass 300 lines
- `apps/mobile/src/screens/debug/DebugScreen.tsx`
- `apps/mobile/verification/ui/run.py`
- `apps/mobile/verification/ui/live-activity.py`
- `apps/mobile/verification/ui/README.md`

Requirements:

- Debug page row "Live Activity 演示" opening a scene with three rows: "开始（运行中）",
  "切换为需要授权", "结束", calling `debugLiveActivity`. Include the settings toggle
  row rendered through the production `NotificationSettingsContent` with an injected
  `liveActivity` service so the toggle is exercised offline. Test ids:
  `live-activity-preview-ready`, `live-activity-start`, `live-activity-permission`,
  `live-activity-end`.
- `verify:ui --case live-activity` (add to `CASES`, `PREVIEW`, ready-id map, and the
  script list in `run.py`): tap start, wait 2 s, capture `island-running` from the
  Simulator screenshot (the Dynamic Island renders on iPhone 17 family simulators;
  the leased device type is whatever the pool creates: read
  `verification/simulator.py` and, if it creates a device without a Dynamic Island,
  change the pool's device type to `iPhone 17 Pro`), tap permission, wait 2 s,
  capture `island-permission`, then press the home button via the AXe driver's
  existing helper (or `xcrun simctl` if the driver lacks one) and capture
  `lockscreen-permission` after locking the device (`xcrun simctl io <udid> ...` has no
  lock; use the driver's existing approach for `background` case to reach the home
  screen and accept a home-screen capture if lock screen capture is not possible,
  saying so in `README.md`). Then tap end and assert the debug status row reads
  "0 个活动".
- Both appearances run automatically through `run.py`.
- Update `README.md` baseline inventory with the new case and its limits.

Test: `python3 apps/mobile/verification/simulator.py --name 'Live Activity' -- zsh -euc '<build to a fresh derivedDataPath with -destination "id=$LODY_VERIFY_UDID">; PATH=<shim>:$PATH python3 apps/mobile/verification/ui/run.py --app <Debug.app> --case live-activity --output .artifacts/live-activity-<n>'`
passes in light and dark, and the captured PNGs visibly show the island states (open
them and describe what is visible in the report).
