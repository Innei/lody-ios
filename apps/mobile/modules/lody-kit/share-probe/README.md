# Share transport probe

This opt-in spike tests the hard requirement: create a new Chat and send its first
text turn from a real Share Extension, while the containing app is stopped.
It uses the existing Cloud protocol unchanged. It is not the production share UI.

The extension compiles UIKit/WebKit, the existing `AuthKeychain` and native
`RuntimeHealth`. It bundles the existing `DataRuntime.html` and its dependency
licenses, without linking Expo, OneSignal or the app's Swift runtime owner.
The full JS runtime is intentionally reused for the first feasibility measurement;
its live catalog memory cost has to be measured before selecting a smaller bundle.

The extension is entitled to read the containing app's existing default Keychain
access group. It does not migrate or copy credentials. Sign in using the iOS
app's official Device Flow. Only workspace Streams grants enter the WebView.
Workspace and agent choices load live. The probe uses agent defaults, no model
picker, project picker, attachments, app launch or composer handoff.

## Build

From the repository root:

```sh
LODY_SHARE_PROBE=1 pnpm prebuild
LODY_SHARE_PROBE=1 pnpm --filter @lody-ios/mobile pods
pnpm verify:simulator --name 'Share Probe' -- pnpm verify:build
```

`LODY_SHARE_PROBE=1` must also be set on any later pod install that should retain
the probe. An ordinary pod install removes this generated probe target and its
embedding; no production share entry is shipped by default.

## Checks

```sh
pnpm verify:native --case share-probe
python3 apps/mobile/verification/ui/share-probe.py --app /absolute/path/to/Lody.app
```

The second check leases its own Simulator and invokes the real system share sheet
from a tiny signed fixture app. It verifies text ingestion, the signed-out state
and cancellation with the containing app stopped. It never authenticates or sends.
Screenshots and accessibility snapshots are written under `.artifacts/share-probe/ui`.

For live delivery, use an explicitly chosen test device with the iOS app signed
in and an online machine. Share a harmless test message through **Lody** in the
system sheet (the extension's title is **Lody Send Probe**),
select its workspace/agent, stop the containing app, then tap Send. The probe keeps
the machine ACK and session ID visible instead of auto-closing, so the observer can
check the same session and first message in Lody. Record time, extension/WebContent
memory and the actual transcript; a build or a local fake ACK is not delivery proof.

## Failure semantics

Before the first network write the probe atomically saves a receipt to App Group
`Library/LodyShareProbe/<sessionId>.json`. It contains the text and stable session/
turn IDs, not credentials. Creation precedes session synchronization and sending.
Only `accepted` is displayed as machine acknowledgement; `uploaded` and `unknown`
remain unconfirmed. An interrupted/uncertain attempt is never automatically replayed.
Inspect its session before trying another share. Receipts are diagnostic recovery
records, not a main-app outbox and not yet a production recovery UI; remove them
with the test app/container when finishing the spike.

The native startup/heartbeat and command deadlines terminate a wedged runtime.
There is no background task, automatic runtime restart or automatic write retry.
The next production design depends on a successful authenticated run, including
account switching, lost ACKs, and actual device memory limits.

## Local evidence — 2026-09-18

`pnpm check`, `pnpm bundle`, the normally signed Simulator build and the native
submission behavior check passed. The real system-share smoke check passed with
the containing app stopped: text arrived, the login notice appeared, Send's
accessibility state was disabled, and Cancel dismissed the extension. Screenshots
were also visually inspected. AXe's point queries expose the remote extension's
controls even though its full source-app tree omits them.

On the user-authorized, signed-in iPhone 17 Pro Simulator, the real extension
loaded workspaces and agents with the containing app stopped. Selecting
**Grok** and submitting the harmless text created a session.
The first attempt stopped before sending:
`ensureSession` returns the string `watching`, but the probe expected an object.
The remote transcript was empty; the saved receipt remained `unknown` and was
not replayed. The bridge now wraps that readiness result, and submission checks
it before sending. The native behavior check and signed Simulator rebuild passed.

A second attempt was initially paused while another automation controlled the
same Simulator. After the user released the device, the corrected extension
created a new session using the same Grok agent.
The extension displayed a machine ACK and persisted phase `accepted`.
A separate read of the remote transcript
confirmed exactly one user message and the assistant response **OK**. Transcript
timestamps were `2026-09-17T16:29:28.682Z` and `2026-09-17T16:29:30.162Z`.
The containing app was stopped throughout; process inspection confirmed only
its Share Extension was running on this device.

This verifies authenticated creation, first-turn machine acknowledgement and
an actual Grok response from the real system Share Extension on Simulator,
without changing Cloud or launching the containing app. Recording:
`.artifacts/share-probe/ui/live-grok-fixed.mp4`; ACK screenshot:
`.artifacts/share-probe/ui/live-grok-fixed-result.png`.
The extension's post-send RSS sample was 323,824 KiB (Simulator only, not a peak
or physical-device memory acceptance). Physical-device memory limits and the
remaining failure/account-switch scenarios still need verification.

The PR-time `pnpm check` passed, including formatting. Test account/session IDs,
recordings and runtime receipts are retained locally, not published in this PR.

### Memory gate — pending physical device

`vmmap -summary` on the authenticated Debug Simulator run reported the following
physical footprints (MiB, not RSS). These are individual process lifetime peaks,
not a simultaneous combined peak or an iOS extension memory-limit assertion.

| State                        | Extension | Extension peak | Owned WebContent | WebContent peak |
| ---------------------------- | --------: | -------------: | ---------------: | --------------: |
| After successful send        |      45.9 |           73.0 | Already released |    Not captured |
| Reopened, live catalog ready |      46.5 |           73.0 |            105.7 |           153.7 |
| Three seconds after Cancel   |      46.2 |           73.0 |   Process exited |               — |

The new WebContent PID appeared when opening this extension and exited on its
cancellation; unrelated macOS WebContent processes were excluded. No additional
message was sent during this read-only catalog measurement. This single reopen
does not establish leak freedom, worst-case catalog cost, or attachment headroom.

Both registered iPhones (12 and 17) were offline in `devicectl` and `xctrace`.
**Memory acceptance has not passed; production implementation remains gated.**
Next: connect a trusted developer-enabled iPhone, run a normally signed Release
build with representative authenticated catalogs, measure cold/open/send/close
and repeated cycles, and inspect memory termination diagnostics. Simulator
measurements cannot validate device memory limits; see Apple's
[Simulator session](https://devstreaming-cdn.apple.com/videos/wwdc/2019/418o9bbtoe880sauh/418/418_getting_the_most_out_of_simulator.pdf).
