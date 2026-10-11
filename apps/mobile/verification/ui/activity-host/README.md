# Live Activity verification hosts

These two **verification-only** targets compile the production model, SwiftUI
views and asset catalog. They are not shipped, do not read Keychain or connect to
Cloud, and contain no alternate implementation of the UI.

- `LodyActivityVerify` owns real ActivityKit activities and embeds the production
  `LodyLiveActivity` extension. Use it for Lock Screen, Dynamic Island and paired
  Watch forwarding. Its bundle identifier is `app.innei.lody`, so install it only
  on a leased verification Simulator. It replaces the product app on that device.
- `LodySmallActivityVerify` directly hosts `LodySmallActivityView` on watchOS at
  152 × 69.5 and 184 × 80.5 pt. Captures visibly say **Production view fixture**;
  they prove native layout, **not** Smart Stack mirroring or the system platter.
  Reduced luminance is injected at the environment boundary, not a proof of
  physical Always-On Display behaviour.

Prepare the generated Xcode targets after `pnpm prebuild`:

```sh
cd apps/mobile
PATH="$(brew --prefix ruby)/bin:$PATH" bundle exec ruby verification/ui/activity-host/prepare.rb
```

The recipe adds only verification targets and the ordinary production widget to
Expo's generated project. It does not edit Pods or change the production scheme.
Both targets use normal Xcode signing and the same workspace DerivedData as the
app. Production builds still use `pnpm --filter @lody-ios/mobile pods`.

Run native Watch checks (repeat with `--device watch-small` for 40 mm):

```sh
pnpm verify:simulator --name 'Watch Activity' --device watch -- zsh -euc '
  watch_app=$(pnpm --silent verify:build --scheme LodySmallActivityVerify --sdk watchsimulator)
  python3 apps/mobile/verification/ui/watch-activity.py --app "$watch_app" --output .artifacts/watch-live-activity/watch45
'
```

Run the phone host inside a separate `pnpm verify:simulator` lease, building with
`pnpm verify:build --scheme LodyActivityVerify`. Install the returned app; launch
with `-AppleLanguages '(en)' -AppleLocale en_US`. Buttons named `activity-single`,
`activity-running`, `activity-permission`, `activity-question`, `activity-done`,
`activity-failed`, `activity-doneMany`, `activity-stale`, and `activity-end` drive
fixtures. The host shows `Showing <state>` only after ActivityKit accepts the
change. Allow the first system Live Activity prompt on the Lock Screen.

For mirroring, hold both leases, pair their UDIDs with `simctl pair`, and inspect
the Watch Smart Stack. Record both the pairing state and actual Watch content;
`active, connected` alone does not prove an activity arrived. Unpair the owned
pair before releasing the leases. Do not change other devices or account settings
in an attempt to make mirroring work.

`watch-activity.py` waits for each production title in Accessibility, excludes
black launch-transition frames, captures PNG + AX JSON and records entry timings.
Every screenshot still needs visual review. The fixture screen is not an
approximation of the system Smart Stack and must never be reported as one.

Coverage includes running, overview, permission, question, completion, failure,
multiple completions, stale and reduced luminance. English is the single UI
verification locale. Phone Lock Screen / Island should be checked in light/dark;
Watch Smart Stack uses its dark appearance.

After installing the phone host, run `python3 apps/mobile/verification/ui/activity-host-phone.py <output>` within its lease to capture running, permission and completed states on the actual Lock Screen and Dynamic Island in both appearances, with video. This checks the production Widget; full-app catalog delivery and deep-link handling remain separate.
