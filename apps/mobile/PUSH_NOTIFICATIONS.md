# Native OneSignal integration

The iOS-only app keeps bundle ID `app.innei.lody` and uses the public OneSignal App
ID `e383bf31-7c8e-4641-b3f6-3486e77b9a82`. `LODY_ONESIGNAL_APP_ID` can override it at
prebuild time (an empty value disables initialization). No REST API key or APNs
private key is shipped in the app.

OneSignal iOS **5.5.1 Stable**, selected from the official
https://onesignal.github.io/sdk-releases/releases.json, is pinned in LodyKit's podspec
and the config plugin. CocoaPods installs the native SDK; there is no RN OneSignal
bridge. LodyKit owns initialization, identity, subscription observation, click
buffering and foreground policy. The Notification Service Extension uses the same
SDK version and App Group `group.app.innei.lody`.

## Build and configure

1. Configure this OneSignal App's iOS platform for `app.innei.lody` and its APNs key.
2. Keep automatic signing and choose your Apple team. Register Push Notifications
   and the App Group for the app, and the same group for the NSE identifier
   `app.innei.lody.notification-service` and the widget extension identifier
   `app.innei.lody.live-activity`.
3. Run `pnpm prebuild`, then `pnpm --filter @lody-ios/mobile pods`. The Podfile helper
   idempotently creates the generated NSE and Live Activity widget targets before
   CocoaPods analyzes them.
4. Build the signed workspace (`pnpm ios`, or `xcodebuild` with normal signing).
   The app embeds `LodyNotificationService.appex` and `LodyLiveActivity.appex`. Changing the OneSignal App ID or
   native configuration requires a new native build, not an OTA update.
5. Configure Convex's generic `ONE_SIGNAL_APPS` inventory and the new app's secret
   API key as documented in that backend's `PUSH_NOTIFICATIONS.md`.

## Runtime behavior

The native SDK requests notification permission immediately after OneSignal
initialization during app launch. iOS displays the system prompt only while the
authorization status is undetermined; after a denial, Settings → Notifications is the
manual entry. After account restoration, the SDK uses the Better Auth user ID as its
external ID. Login does not trigger another permission request. Logout detaches and
opts out the current subscription, clears delivered notifications, and drops buffered
clicks. Offline logout cannot synchronously revoke a remote provider binding; use
neutral lock-screen previews.

The SDK's Web launch URL is suppressed. RN handles `data.route` after auth and
navigation become ready, checks the recipient and workspace, selects the workspace,
then resolves the real Session from its catalog. Missing sessions wait during sync;
completed sync reports an unavailable session. Foreground notifications for the
focused session are suppressed. Permission data opens the session rather than
executing an approval from a notification.

The Debug page's **Verify OneSignal subscription** action observes a real server
subscription (nonempty, not `local-`) and shows the official integration dialog once
per process; the button can request permission. This developer-only scaffolding is
kept out of product flows. Only subscription readiness is exposed, not token/ID data.
In-app messages, email/SMS, and tags are not enabled by this integration.

## Live Activity

The widget extension renders `LodyConversationLiveActivityAttributes` (locally
aliased as `LodyActivityAttributes`) on the Lock Screen and in the
Dynamic Island. Its rows deep-link with the `lody://` scheme
(`lody:///{workspaceSlug}/sessions/{sessionId}`); a workspace without a slug routes by
its id instead, and unmatched paths redirect to the home route. Settings →
Notifications carries the Live Activity toggle, which stores its state in the App Group
and ends every running activity when turned off.
`withSceneLifecycle` passes cold-start URL contexts to React Native launch options
and forwards warm scene URLs through the existing Expo AppDelegate linking handler.

Sources and `AgentIcons.xcassets` live in `modules/lody-kit/live-activity/` and are
copied into `ios/LodyLiveActivity/` by the Podfile helper, so editing them requires a
fresh `pod install` before the next build. The catalog carries eleven agent marks from
Lobe Icons (MIT, `modules/lody-kit/licenses/LobeIcons-LICENSE.txt`) as template images
and is also linked into the application by `withLodyIcons`, where `agentIcon()` picks the
same names for grouped rows; unknown agents fall back to their two-letter glyph. Widget
strings travel in the content state's `copy`; missing keys default to English.

The app requests an activity itself with `pushType: .token` and hands the token to
OneSignal. The native owner uses OneSignal's manual registration API, not automatic
`setup`: it observes both current and future activity tokens and push-to-start
tokens. Registration requires an initialized SDK, an identified user, the app toggle
and system authorization. Turning the toggle off removes the push-to-start token;
account changes detach registrations and end the old activities before OneSignal
changes identity. Offline Debug scenes never register tokens.

Convex `notifications.syncLiveActivitySummary` updates the v5 activity ID
`lody-conversations:v5:<workspaceId>:<userId>`. When `permissionAlert` is present,
it also sends a start to `activities/activity/LodyConversationLiveActivityAttributes`.
The concrete Swift type name must match this path. The existing backend attributes
contain `activityId`, `workspaceId`, `workspaceName`, but no `userId` or
`workspaceSlug`: decoding recovers the owner from the exact v5 workspace prefix,
rejects inconsistent identities, and falls back to the workspace ID for navigation.
OneSignal metadata and optional future fields are tolerated. Update/end content
decodes directly into the same Widget state without a second RN replica.

Every live catalog snapshot reconciles the existing activity. Running and waiting
turns remain; completed, failed, archived and idle sessions leave. Unread replies
never enter widget focus. Multiple running turns show a count and stable session
links, while a pending question or permission takes focus. The overview opens
`/activity` with account/workspace validation and the existing native session rows.
When no work remains, the app ends the activity with the finished rows marked
completed (or failed for `error` sessions), their frozen turn durations, and a
60-second Lock Screen dismissal date. A subsequent turn creates a new activity.
Timers start at the session's `lastRunningSeen` (the current turn), never at the
previous message or the session creation; the widget replaces raster images larger
than their frame with a grey box, so the jellyfish ships at exact 1x/2x/3x sizes.

The inspected Convex backend already sends a 30-minute `stale_date` and an
immediately dismissed `end` when its summary becomes empty. Its existing summary
may include unread replies, so its termination condition differs from local
running/waiting reconciliation. It remotely starts only for permission alerts;
starting an ordinary turn while the app is closed does not by itself start a new
activity. Local reconciliation runs only while the catalog runtime can execute.
Real background APNs delivery still requires device verification below.

### Enable native iOS on the existing backend

No Convex schema change or new device-token endpoint is required. In the deployment
that serves the app, add/update this entry in the **complete** `ONE_SIGNAL_APPS`
JSON array (keep all existing app entries):

```json
{
  "name": "native-ios",
  "appId": "e383bf31-7c8e-4641-b3f6-3486e77b9a82",
  "apiKeyEnv": "ONE_SIGNAL_IOS_API_KEY",
  "push": true,
  "liveActivities": true
}
```

Set `ONE_SIGNAL_IOS_API_KEY` to this OneSignal app's REST API key in Convex's
environment variables. This is distinct from the APNs `.p8` signing key: configure
that key, its Key ID and Apple Team ID in the OneSignal iOS platform dashboard for
bundle `app.innei.lody`. Live Activities require `.p8` authentication; an existing
`.p12` ordinary-push configuration is insufficient. Neither secret belongs in Expo environment variables,
the repository, or the widget. An explicit inventory replaces legacy environment
fallback; do not overwrite it with only the new iOS entry.

Apple Developer / signing checklist:

- Main App ID `app.innei.lody`: Push Notifications and App Group
  `group.app.innei.lody`.
- NSE ID `app.innei.lody.notification-service` and Widget ID
  `app.innei.lody.live-activity`: same App Group and Apple team. Keep automatic
  signing; regenerate profiles if their capabilities changed.
- Prebuild owns `NSSupportsLiveActivities`, the remote-notification background
  mode and entitlements. Pod install embeds both extensions. There is no extra
  Live Activity permission prompt to request through RN, and no continuous
  background execution entitlement is needed.
- Rebuild and install the native app. In iOS Settings allow Live Activities for
  Lody, and enable the in-app Notifications → Live Activity toggle.

Device rollout check (use only an account authorized in this app): launch and log
in once to register tokens, start a running session, background/lock the phone,
then observe a server update. With no existing activity, trigger a normal agent
permission request to exercise remote start; tap it to open the correct workspace
and session. Resolve it inside the app (the old Capacitor widget's inline permission
AppIntent is intentionally not used here). Check server end, toggle off/on, logout,
and switching accounts. Do not treat a successful REST response or a Simulator
fixture as proof of APNs delivery. Offline logout cannot instantly retract an
already queued remote start; reconnect and verify cleanup during rollout.

References: [OneSignal manual Live Activity registration](https://documentation.onesignal.com/docs/en/mobile-sdk-reference),
[OneSignal Live Activity requirements](https://documentation.onesignal.com/docs/en/live-activities-developer-setup),
[OneSignal start API](https://documentation.onesignal.com/reference/start-live-activity),
[Apple ActivityKit push delivery](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications).

## Verification

- `pnpm check`, `pnpm test`, `pnpm bundle`, signed iOS Simulator build.
- `pnpm verify:native --case live-activity` exercises the exact Convex start
  attributes, identity rejection, content decoding and local catalog behavior.
- `pnpm verify:ui --app <Debug.app> --case live-activity` exercises the shared
  Widget using attributes decoded from the Convex schema, without contacting APNs.
- `pnpm verify:ui --app <Debug.app> --case notifications`.
  Both appearances exercise the production settings with injected outcomes. The
  native SDK is disabled under `--ui-verify`, so these checks create no subscriptions.
- With real APNs configured, use a normal install/relaunch preserving app data.
  Log in, grant permission, send a test notification to this installation, and check
  foreground/background, cold-start navigation, account switching, and an image
  notification (NSE). Check signed Push/App Group entitlements and extension embedding.
  Never uninstall/reset just to repeat OneSignal registration verification.

Offline checks prove local behavior and build wiring, not provider delivery. Real
push delivery and backend activation require the configured OneSignal/APNs account.
