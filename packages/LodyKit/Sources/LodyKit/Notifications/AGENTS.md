# Native notification ownership

- `PushNotifications.swift` owns OneSignal initialization and user binding.
- `LiveActivities.swift` owns ActivityKit observations and lifecycle cleanup.
- `LiveActivityRegistration.swift` tracks submitted tokens and observation stamps,
  not server registration success. OneSignal 5.5.1 enter/exit callbacks acknowledge
  enqueueing only; never label them as network success/failure.
- Identical tokens do not supersede SDK cached requests. Foreground/subscription
  readiness re-submits live tokens and invokes the SDK's public start hook for
  pending-cache recovery, throttled to one poll request per 30 seconds.
- Replacing a native instance under the same server Activity ID must not issue
  exit. A delayed DELETE can remove the replacement token. End/logout still exit.
- Tokens remain in memory and must never enter diagnostics. Deterministic checks:
  `pnpm verify:native --case live-activity-registration`. APNs delivery needs a device.
