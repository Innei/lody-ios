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
Live Activities, in-app messages, email/SMS, and tags are not enabled by this change.

## Live Activity

The widget extension renders `LodyActivityAttributes` on the Lock Screen and in the
Dynamic Island. Its rows deep-link with the `lody://` scheme
(`lody:///{workspaceSlug}/sessions/{sessionId}`); a workspace without a slug routes by
its id instead, and unmatched paths redirect to the home route. Settings →
Notifications carries the Live Activity toggle, which stores its state in the App Group
and ends every running activity when turned off.

Sources and `AgentIcons.xcassets` live in `modules/lody-kit/live-activity/` and are
copied into `ios/LodyLiveActivity/` by the Podfile helper, so editing them requires a
fresh `pod install` before the next build. The catalog carries eleven agent marks from
Lobe Icons (MIT, `modules/lody-kit/licenses/LobeIcons-LICENSE.txt`) as template images
and is also linked into the application by `withLodyIcons`, where `agentIcon()` picks the
same names for grouped rows; unknown agents fall back to their two-letter glyph. Widget
strings travel in the content state's `copy`; missing keys default to English.

The app requests an activity itself with `pushType: .token` and hands the token to
OneSignal. Push-to-start is registered when the toggle is on, but the backend calling
it is **unconfirmed**: no server-started activity has been observed from this app.
Attribute decoding therefore tolerates a missing `workspaceSlug`.

`stale-date` and `dismissal-date` are set only on the activity the app requests. Every
later server update must carry its own values; ActivityKit does not inherit them from
the previous content, so an update without them leaves an activity that never goes
stale and never dismisses.

## Verification

- `pnpm check`, `pnpm test`, `pnpm bundle`, signed iOS Simulator build.
- `pnpm verify:native --udid <disposable simulator>`.
- `pnpm verify:ui --udid <disposable simulator> --app <Debug.app> --case notifications`.
  Both appearances exercise the production settings with injected outcomes. The
  native SDK is disabled under `--ui-verify`, so these checks create no subscriptions.
- With real APNs configured, use a normal install/relaunch preserving app data.
  Log in, grant permission, send a test notification to this installation, and check
  foreground/background, cold-start navigation, account switching, and an image
  notification (NSE). Check signed Push/App Group entitlements and extension embedding.
  Never uninstall/reset just to repeat OneSignal registration verification.

Offline checks prove local behavior and build wiring, not provider delivery. Real
push delivery and backend activation require the configured OneSignal/APNs account.
