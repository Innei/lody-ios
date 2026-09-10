# Lody iOS acceptance

## 1. Project summary

Expo Router iOS app in apps/mobile; UIKit capabilities live in LodyKit.

## 2. Environment

Use `pnpm start` for Metro. For a verified signed build, use the managed lease
wrapper below and pass `$LODY_VERIFY_UDID` as the xcodebuild destination; do not
use `pnpm ios`, which lets Expo select another Simulator. Check listening Node
processes before starting a server; do not stop servers owned by another task.
Metro currently uses 8081. Generate assets with
`pnpm --filter @lody-ios/mobile native:assets` before direct xcodebuild.

## 3. Auth

UI regression baselines use `pnpm verify:ui --app <Debug.app>` and automatically
lease a reusable `Lody * Verify` Simulator. For a build plus multiple checks, use
`pnpm verify:simulator --name '<current verify>' -- <command>` and target
`$LODY_VERIFY_UDID`; nested verify commands reuse that lease. Never call
`simctl create` directly for local verification. Explicit `--udid` is reserved
for a caller-owned device such as CI, which also owns its cleanup.
For a local full run, `pnpm verify:ui --parallel --app <Debug.app>` starts one
Metro and three independently leased Simulators. Do not wrap this parallel
command in a single-device lease. The runner owns an isolated Metro (default
8097, override with `--port`) with `EXPO_PUBLIC_UI_VERIFY=1`; account restoration
and login are disabled, and Debug scenes use production components with local fixtures.
Reuse one `--output` path per verify (retries replace it); never suffix `-1`/`-2`
unless comparing two builds. Build with `-derivedDataPath /tmp/lody-build`, never
under `.artifacts`. No account, cloud credentials or connected machine is needed. See
`apps/mobile/verification/ui/README.md` for cases, evidence and CI setup.

Official Lody Device Flow and simulator Keychain only. Inspect the simulator UI for existing login; never copy desktop credentials. No seeded account is provided. Unauthenticated checks must be reported separately from authenticated flows.

## 4. Surfaces

Use AXe with explicit simulator UDID and simctl screenshots. Build workspace apps/mobile/ios/Lody.xcworkspace, scheme Lody, with normal signing. Bundle identifier app.innei.lody. Run pnpm check, pnpm test and pnpm bundle as supporting gates.

UI evidence for a visual or interaction requirement alignment comes from a finished
`pnpm verify:ui` run exported by `apps/mobile/verification/ui/acceptance-round.py`
(claims file + `lh acceptance run ingest`). Export and ingest by hand, only for
that alignment; regression runs stay programmatic gates and are never ingested.

## 5. Project probes & quick navigation

`xcrun simctl list devices booted`; `axe describe-ui --udid <id>`. Product tabs are sessions, settings and search. Development-only Debug lives under Settings.

## 6. Known constraints

Cloud data requires app-authorized login and a connected computer. Do not send real turns merely to verify layout. Preserve all pre-existing working-tree edits. Simulator cannot prove physical haptics.
