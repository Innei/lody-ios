# Live Activity (Dynamic Island) design

Date: 2026-09-09

## Goal

Show the workspace's active agent sessions in the Dynamic Island and on the Lock
Screen, including sessions started from the desktop, with one source of truth and a
system-native look. Replace the upstream "conversation list" presentation with a
single-focus presentation while reusing the upstream push channel unchanged.

## Non-goals

- Allow / reject buttons inside the Live Activity. Tapping opens the session; the
  user approves in the app. Revisit after the push channel proves reliable.
- Per-session activities. One activity per workspace and user.
- Backend changes. The upstream Convex action `syncLiveActivitySummary` and its v5
  payload are the contract.

## Data contract

The activity id is the upstream format:

```
lody-conversations:v5:{workspaceId}:{userId}
```

`LodyActivityAttributes` (fixed for the activity's life):

| field         | type   |
| ------------- | ------ |
| workspaceId   | String |
| workspaceName | String |
| userId        | String |

`ContentState` mirrors the upstream v5 payload field for field and is `Codable`:

| field           | type                                           |
| --------------- | ---------------------------------------------- |
| totalCount      | Int                                            |
| statusCounts    | { permission, question, running, unread: Int } |
| items           | [Item] (up to 8)                               |
| permissionAlert | { title, body }?                               |

`Item`: `id`, `status` (`permission` / `question` / `running` / `unread`),
`statusLabel`, `permissionRequestId?`, `permissionCommand?`, `agentLogoKind`,
`agentLogoText`, `title`, `updatedAt` (ms), `updatedAtLabel`.

Two pure functions live on `ContentState` and are compiled into both the app and the
widget:

- `focus`: the item with the highest priority (`question` > `permission` >
  `running` > `unread`), ties broken by newest `updatedAt`.
- `others`: the remaining items in the same order, capped at 2 for the expanded view.

The exact JSON the server sends through OneSignal must be confirmed before the
decoder is finalized (see Spikes).

## Presentation

Colors are system semantic colors only: blue for running, orange for "needs you"
(permission and question share it), green for completed. No brand imagery; the agent
glyph is the two-letter `agentLogoText` on a neutral rounded square.

### Compact (Dynamic Island)

Leading: focus item's agent glyph. Trailing: a symbol only.

| focus status          | trailing                  |
| --------------------- | ------------------------- |
| running               | indeterminate ring (blue) |
| permission / question | orange dot                |
| unread                | green checkmark           |

Minimal (another app owns the island): the trailing symbol alone.

### Expanded (long press, or automatic on an alert update)

Top row: agent glyph, session title (single line), status line with the same symbol
and label, and on the right a native `Text(timerInterval:)` counting up from the
focus item's `updatedAt` when running, or a "查看" pill otherwise.

Permission state adds the `permissionCommand` in a monospaced strip below the title.

Below a hairline: up to 2 other items as rows (glyph, title, status symbol). Each row
is a `Link` to its session.

### Lock Screen and StandBy

Focus row only: glyph, title, status line, timer or pill. Other sessions collapse into
the status line as "还有 N 个在跑". No list.

### Alerts

Updates whose focus becomes `permission` or `question` arrive with an alert
configuration (screen wake, one highlight, haptic). Running and unread updates are
silent. The alert is decided by the server payload's `permissionAlert`; the widget
never invents one.

## Lifecycle

### Start

- While the app process is alive, `LiveActivities` in LodyKit observes the
  DataRuntime catalog projection. When the workspace has a running or awaiting
  session and no activity exists, it calls `Activity.request` with an initial
  `ContentState` built from the local catalog, then hands the update token to
  OneSignal via `LiveActivities.enter(activityId, token)`.
- On launch it reports the push-to-start token with
  `LiveActivities.setPushToStartToken`. Whether the backend uses it is unknown (see
  Spikes). If it does not, a killed app does not surface desktop-started sessions
  until the next launch; this is a documented limitation, not a bug.

### Update

- Only server pushes change content after the initial request. The app never writes
  `ContentState` again; this removes the upstream dual-writer race.
- Focus selection happens inside the widget from the pushed payload.

### End

- Server `ended` pushes end the activity.
- An `unread` focus with no running or awaiting items dismisses itself 15 minutes
  after the last update via `dismissalPolicy(.after(_:))`.
- `staleDate` is 30 minutes after the last update. Stale content renders grey with
  "已断开"; opening the app refreshes or ends it.
- Logout and the settings toggle end the activity immediately and clear the OneSignal
  token association.

### Tap

- Compact, minimal, lock screen card, and the expanded focus area open the focus
  session.
- Expanded rows open their own session.
- All use `widgetURL` / `Link` with `lody:///{workspaceSlug}/sessions/{sessionId}`.
  The app's Linking handler feeds the path into the existing notification routing
  (`parseNotificationRoute`, `resolvePushDestination`) so workspace switching and
  "session not synced yet" waiting are shared with push clicks.

### Scheme

The app scheme changes from `lody-ios` to `lody`. Notification clicks and widget
links share the `lody://` route space. Nothing in the codebase depended on the old
value.

## Components

### Widget extension target `LodyLiveActivity`

- Bundle id `app.innei.lody.live-activity`, registered with Push Notifications and
  the `group.app.innei.lody` App Group, automatic signing.
- Created by a Ruby helper alongside `push-extension.rb` and invoked from the Podfile
  via the config plugin, so it survives prebuild. Generalizing the helper into
  `lody_extension(name:, kind:)` is acceptable if the diff stays small.
- Sources live in `modules/lody-kit/live-activity/`: `LodyActivityAttributes.swift`
  (shared), `LodyLiveActivityWidget.swift`, `CompactViews.swift`,
  `ExpandedView.swift`, `LockScreenView.swift`. The helper copies them into the
  generated target.

### LodyKit `Notifications/LiveActivities.swift`

- `@MainActor` singleton next to `PushNotifications`.
- Subscribes to DataRuntime catalog events; owns `Activity<LodyActivityAttributes>`
  request, token forwarding to OneSignal, push-to-start token reporting, and
  `end(immediate)` on logout or toggle off.
- Exposed to RN through `LodyKitModule`: `setLiveActivitiesEnabled(Bool)` and
  `liveActivityStatus()` returning `{ enabled, active, supported }`.
- Enabled flag persists in `UserDefaults` under the app group so the widget can read
  it if needed.

### React Native

- `NotificationSettingsScreen`: a "灵动岛" toggle row under the notification
  permission row.
- Root layout: `Linking` handler for `lody://` paths routed through
  `PushCoordinator`'s destination resolution.
- `models`: no change; the widget consumes the pushed payload, not the RN catalog.

## Verification

- `modules/lody-kit/verification/live-activity`: deterministic Swift check decoding
  an upstream sample payload, focus priority and tie-breaking, `others` capping,
  stale and dismissal date computation.
- Debug page scene "Live Activity 演示": start with an injected `ContentState`,
  update to a permission state, end. No cloud access, no OneSignal initialization.
- `verify:ui --case live-activity`: screenshots of the compact island and the lock
  screen card in running and permission states on a Dynamic Island simulator.
- Existing `notifications` case is extended to cover the settings toggle.

## Spikes before implementation

1. Capture or read the exact OneSignal `event_updates` JSON the upstream Convex
   action sends, to pin the `ContentState` decoder. Preferred: read the backend
   source if available; fallback: capture one real push on a device.
2. Confirm whether the backend calls OneSignal push-to-start. Determines the
   documented limitation in Lifecycle / Start.

## Open risks

- ActivityKit push payloads are capped at 4 KB. Eight items with commands can exceed
  it; the server already truncates for the upstream client, so the decoder must
  tolerate missing optional fields rather than fail.
- The Lock Screen and StandBy render the same `ActivityConfiguration` content; the
  focus-only layout must remain legible at StandBy scale.
- Under the single-writer rule the app sets `staleDate` and `dismissalDate` only on the
  activity it requests itself. ActivityKit does not carry them forward across updates,
  so every later server-pushed update must send its own `stale-date` and
  `dismissal-date`. An update that omits them produces an activity that never marks
  itself stale and never auto-dismisses, and the app will not correct it because it
  never rewrites an activity it did not start in that pass.
