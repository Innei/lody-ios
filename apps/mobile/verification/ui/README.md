# Offline UI verification

All UI baselines run without login, user data, cloud credentials, or a connected
machine. `EXPO_PUBLIC_UI_VERIFY=1` in a **development** bundle prevents account
restoration before Keychain/SQLite reads and disables login. The runner starts
its own Metro and requires the `ui-verify-ready` marker before any interaction.
Native image fixtures additionally require the `--ui-verify` launch argument and
compile only in Debug. No production credentials are used. The managed verification
Simulator is reused without erasing between leases.

## Run locally

If a normal signed Debug app is already built, each verification command can lease
its own iPhone 17 Pro / iOS 26.5 device from the `Lody * Verify` pool:

```sh
pnpm verify:native
pnpm verify:ui --app /absolute/path/to/Lody.app
pnpm verify:ui --app /absolute/path/to/Lody.app --language zh-Hans --output .artifacts/ui-zh
```

For a verified build, wrap the build and checks so Xcode cannot select a personal
Simulator. The wrapper exposes its device as `LODY_VERIFY_UDID`; nested verify
commands use that lease automatically:

```sh
pnpm verify:simulator --name 'File Preview' -- zsh -euc '
  pnpm --filter @lody-ios/mobile native:assets
  xcodebuild -workspace apps/mobile/ios/Lody.xcworkspace -scheme Lody \
    -configuration Debug -sdk iphonesimulator \
    -destination "id=$LODY_VERIFY_UDID" \
    -derivedDataPath /tmp/lody-build build
  pnpm verify:native
  pnpm verify:ui --app /tmp/lody-build/Build/Products/Debug-iphonesimulator/Lody.app \
    --case file-preview --output .artifacts/file-preview
'
```

The allocator serializes selection and locks each leased device. It only considers
available, matching `Lody * Verify` devices; personal devices, other projects and
legacy runtimes are never candidates. Reserve that name pattern for disposable
verification devices. A shutdown candidate is renamed to the current
verification, then booted. If none is free, one device is created.
Release shuts it down but keeps it for the next run. A device left booted after an
interrupted managed run can be reclaimed once its lock is gone; an untracked booted
device is treated as occupied.

`--udid` remains available for CI or an explicitly owned Simulator. Supplying it
bypasses leasing, rename and shutdown, so its caller owns the full lifecycle.
Do not call `simctl create` directly for local verification.

Requires Python 3, AXe 1.8.0, Xcode 26.5 and the workspace dependencies.
`--case layout` selects one case (still both appearances). `--language` picks the
App Language the run launches with (`en` by default) and the catalog the scenes
assert against; run both before claiming bilingual coverage. `--port 8098` changes
the isolated Metro port; occupied ports are rejected. `--output PATH` selects an
artifact directory; use a new path for each run. The runner owns only its Metro
process group and app process. A small host-only CoreSimulator helper disconnects
hardware keyboard input for the leased device so keyboard geometry is actually
tested. No global Simulator preferences are changed. It never shuts down another
task's locked Simulator or Metro.

## Baseline inventory

`smooth-scroll` exercises cached history replacement, anchor preservation while
reading, streamed paragraphs/code, drag interruption and the production process
Sheet. It records video plus opt-in Debug-only UIKit geometry at display refresh
cadence (`--ui-verify-scroll`); the check requires intermediate scroll/height
frames in both hosts. Review the video for clipping and flashes before claiming
visual smoothness. The probe contains fixture IDs and geometry only.

| Case             | Production surface                                    | Behavior                                                                                                                                                                                                                                                                                                                                          |
| ---------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| notifications    | NotificationSettingsContent                           | Permission request, denial, settings return and reset                                                                                                                                                                                                                                                                                             |
| settings         | RemoteSettingsView + RemoteSettingEditorScreen        | Leading Cancel/trailing Save while typing, compact Machine/MCP sheets, Agent prompt, failed load retry, failed-save Toast with draft retention, and saved-value readback                                                                                                                                                                          |
| home             | InboxScreen header + glass FAB + settings Sheet       | Inbox header search, archived results, cancellation restore; view menu group switching; empty project shows `0`; project/session long-press context menus and session transcript peek; bottom-right glass create repeated open; long-press Settings opens Debug and returns; push remote settings and archive in settings sheet with close/return |
| licenses         | Settings sheet + LicensesScreen + LicenseDetailScreen | App AGPL notice first, then the alphabetical bundled-library list with license ids and versions, full license text on push, back to the list and sheet close                                                                                                                                                                                      |
| onboarding       | OnboardingScreen (non-dismissable pageSheet)          | No close button, swipe-down resists, connect → waiting code → cancel error → retry, sheet closes itself on sign-in                                                                                                                                                                                                                                |
| send             | NativeChat + shared send lifecycle                    | Offline immediate user/static timer rows, no pre-connection dispatch, failed text/attachment restoration, uninterrupted authoritative takeover                                                                                                                                                                                                    |
| send-rounds      | NativeChat with retained history                      | Three accepted turns (short, wrapped, multiline), distinct IDs, cleared drafts, and native frame-by-frame landing checks                                                                                                                                                                                                                          |
| send-queue       | NativeChat + shared send lifecycle                    | Queue above input, draft/Stop switching, selected Steer failure/retry, Stop advances FIFO, no transcript flash or duplicate draft                                                                                                                                                                                                                 |
| send-interrupt   | NativeChat + shared send lifecycle                    | Agent without acknowledged steer: only the first queued message offers Steer, and Steer cancels the running turn so the queue advances FIFO                                                                                                                                                                                                       |
| send-handoff     | NativeComposer sheet → NativeChat push                | Message UIView stays visible across navigation before creation; failed creation restores draft in target input                                                                                                                                                                                                                                    |
| layout           | NativeChat + navigation title                         | Title-tap debug dump with Copy; More menu Project Files separated from pin/archive; stream segments, completion folding, full conclusion, process-row height, send positioning                                                                                                                                                                    |
| duration         | NativeChat assistant duration row                     | Static (non-shiny) first-row duration advances each second; server process follows below; completion freezes the OSS-compatible duration above the final answer                                                                                                                                                                                   |
| tracking         | NativeChat                                            | User drag releases following, stable history, return button during/after streaming                                                                                                                                                                                                                                                                |
| model-memory     | CreateSessionScreen + ModelScreen + NativeComposer    | Per-model effort and permission restoration across both selection hosts, full-access default                                                                                                                                                                                                                                                      |
| model-options    | ChatComposerView                                      | Model/effort controls, RN echo, reopen persistence                                                                                                                                                                                                                                                                                                |
| image-preview    | ChatImageCell + ChatImagePreview                      | Synthetic bitmap, zoom/restore, button and gesture dismissal                                                                                                                                                                                                                                                                                      |
| composer         | NativeComposer in a real form sheet                   | Floating list inset, half/full sheet contrast, last-row reachability, file paste, iOS 26 focus glass fusion with balanced Add/Send controls and trailing model selector, keyboard clearance, rejection restore, duplicate suppression                                                                                                             |
| composer-glass   | NativeComposer in a real form sheet                   | Separate unfocused Add/input glass, focus merge animation and unified final surface, mirrored Add/Send centers, shared baseline, trailing model selector, light/dark screenshots and video                                                                                                                                                        |
| composer-video   | NativeChat composer                                   | Paste a movie that also registers a PNG poster; the chip and sent user row keep the video filename and never open an image cell                                                                                                                                                                                                                   |
| composer-success | NativeChat composer                                   | File paste, pending clear/lock, text and attachments stay cleared after acceptance                                                                                                                                                                                                                                                                |
| markdown         | MarkdownView code block + table                       | Copy preserves complete code and indentation through the Simulator clipboard; a wide table bleeds to the screen edges and keeps that bleed after a horizontal swipe                                                                                                                                                                               |
| live-activity    | LodyLiveActivity widget + NotificationSettingsContent | Fixture activity start, running → permission update, compact Dynamic Island and Lock Screen card captures, end returns the debug status row to `0 个活动`                                                                                                                                                                                         |
| background       | DataRuntime + BGContinuedProcessingTask               | Same WebView cross-background restoration, real system task requests, completion/expiration release; explicitly records unverified long-running execution when system denies request                                                                                                                                                              |
| changes          | NativeChat + shared DOM file diff                     | Grouped file rows after completion, header totals, long paths, reused WebView instance, Unified/Split, hidden warnings                                                                                                                                                                                                                            |
| inline-diff      | ItemDetail DiffBlock + NativeInlineDiff               | Native line content, full height, outer-sheet vertical scroll, selectable rows                                                                                                                                                                                                                                                                    |
| inbox            | NativeGroupedList + inboxSections                     | Dynamic grouping; session rows as conversation list (in-progress dot before title, time on right, confirmation pill); unread completed items do not enter Today                                                                                                                                                                                   |
| composer-failure | NativeChat composer                                   | Pasted-file, text and attachment restoration after rejection                                                                                                                                                                                                                                                                                      |

Every case starts a fresh app process and navigates from Debug. Both light and
dark appearances run with default text size and English system controls. Product
copy is asserted through `catalog.text` / `catalog.plural`, which read the same
`apps/mobile/locales` catalog the app ships, so a scene proves the selected
language rather than a hardcoded sentence. Fixture content remains Chinese. Composer requests remain pending until the driver taps
Complete Request, so request timing cannot hide the busy state. These scenes
exercise production native draft contracts; they do not claim to cover cloud
persistence or Machine RPC. Those retain their existing behavior tests.

`verify:native` reuses chat, watchdog, local-store, status-label rendering,
composer, attachment and inline-diff checks. The former ChatMarkdown-specific drawing and
block-selection tests referenced a deleted renderer and have been retired;
Markdown is rendered by the actual chat baseline, with screenshots/video for
review. There is no pixel-diff gate yet: screenshots are evidence, not automatic
proof of typography or animation quality.

## CI and future UI changes

`.github/workflows/verify.yml` runs Checks and Offline iOS UI on PRs and pushes to
main. Configure both as required checks in the repository branch rules before
relying on them to block merges. UI artifacts contain results.json, per-case
logs, screenshots, accessibility trees and video, including failures. Missing
scenes and timeouts fail the job. No login or distribution signing secret is used.

For each new UI behavior:

1. Add/reset a deterministic scene under development-only Debug. Reuse production
   views and the existing `present` contract; inject data or service outcomes at
   the owning boundary. Do not duplicate a production screen into a fake UI.
2. Add a runnable user-visible assertion and register it in the runner. New scenes
   must run independently without earlier cases or login.
3. Reproduce bugs with the original precondition; avoid internal constant-table
   snapshots. Prefer element-relative geometry and bounded state waits.
4. For shared UI, exercise each real host (e.g. chat and creation sheet). Add
   navigation/return integration cases when those boundaries change.
5. Review screenshots for appearance changes and video for keyboard/scroll/gesture
   changes. Baseline updates require review; never auto-approve a failed comparison.

Remote settings details now have an independent offline scene. It injects service
outcomes and checks the submitted values, but does not claim live cloud persistence.
Product catalog navigation and live cloud workflows still need separate acceptance.

The live-activity case runs via `--case live-activity` against the fixture activity in workspace `debug`; no OneSignal, cloud access or credentials are involved, and the settings toggle row is driven through an injected `liveActivity` service, so the case switches it off and back on and asserts the accessibility value flips both ways without ending the fixture. iOS hides a Live Activity from the Dynamic Island while its own app is in the foreground, so each island capture backgrounds the app first: `island-running` and `island-permission` show the compact island over the Home screen, and `lockscreen-permission` locks the device and captures the Lock Screen card. The first fixture activity on a pool device raises the one-time system "Allow Live Activities" consent alert; pool devices are only shut down and rebooted, never erased, and `run.py` installs once for both appearances, so that alert appears on the first run against a device and never again. The case polls for its Allow button after starting the fixture and once more after locking, and taps it when present, so the captures and the later taps do not depend on which run this is. Push-to-start, remote updates and dismissal timing are not covered here and need a real device.

The background case runs via `--case background`, dwelling on the Simulator Home screen for 40 seconds. Counts originate from real offscreen WebView callbacks; cloud events are substituted with local scripts without network or credential access. If the system denies sustained background tasks, this case only verifies retention/restoration and request-failure degradation, and cannot be used to claim that sustained background execution has passed. Prolonged physical-device network connectivity and power consumption require separate real-device testing.

`--case home` uses an independent `EXPO_PUBLIC_UI_VERIFY_HOME=1` development bundle, injecting in-memory data at the Auth/Catalog Provider boundary without launching authentication or synchronization. A full run executes this scene with an isolated Metro instance first. New session creation only verifies opening and cancelling; projects not bound to a machine do not read machine configuration or send real messages.

### 10,000-message performance demo

Settings → Debug → **10,000-message performance test** (`10,000 条消息性能测试` in the UI) loads 5,000 user messages and
5,000 Markdown answers through the production `NativeChat` collection. Tap the
play button to run a 20-second scroll at 8,000 pt/s (10 seconds away from the
current position, then back). Start at the bottom for the standard baseline.
The timed run visits part of the 10,000-entry dataset, not every message.

```sh
pnpm verify:ui --app <Debug.app> \
  --case chat-performance --output .artifacts/chat-performance --port 8103
```

The recording starts before navigation. `loading.json` records native prop receipt
to first layout and complete history layout, the initial row count, and individual
measurement slices. It excludes JS fixture generation. The check requires a partial
first layout before all 10,000 rows, multiple history measurement slices, and a
stable reading position when history arrives after scrolling during loading. A slice
targets 4 ms; one indivisible message layout may exceed that budget.

The scroll check repeats three times in each appearance. `performance-summary.json`
contains FPS, p95/max frame interval, over-budget intervals, visited section range,
and memory; `run-1.json` through `run-3.json` contain raw samples. Screenshots and
`run.mp4` capture the UI. Assertions verify the full dataset, both scroll directions,
more than 70,000 pt of travel, the measurement interval, and valid memory samples.
Performance values are reported without an arbitrary pass/fail threshold.

FPS measures `CADisplayLink` main-run-loop callback delivery, not GPU-presented
frames. Memory is the whole App process's `TASK_VM_INFO.phys_footprint` in MiB,
sampled every 250 ms; short spikes between samples can be missed. Baseline is
captured when play is pressed, after the dataset is loaded, not an empty-app
baseline. The sampler and video recording add overhead. Simulator Debug results
are regression baselines, not physical-device Release performance or proof of
absence of leaks. Native instrumentation is compiled only in Debug and stops
when its view leaves the window.

### Streaming Markdown pressure checks

`--case chat-stream-performance` drives the production chat with 40 history rows
and 12 seconds of 300 synthetic tokens/s (one token is four UTF-16 units, delivered
in 50 ms batches). It repeats paragraphs, one long paragraph, and one long code
block in both appearances. `stream-summary.json` reports callback FPS, p95 frame
and commit time, text backlog, bottom gap, and catch-up time; `*-samples.json`
retains raw samples. Screenshots and `run.mp4` capture streaming and completion.
Assertions require complete output and final bottom alignment, plus native block
layout parity, unchanged-prefix reuse, and late reference-link resolution.

These are Simulator Debug main-run-loop measurements, not GPU-presented FPS or
physical-device model-token throughput. Compare identical input and appearances;
run `markdown`, `file-preview`, and `smooth-scroll` separately for interaction
regressions. Performance numbers are reported without arbitrary pass thresholds.

### Send animation frame checks

`send`, `send-handoff`, `send-rounds`, and `send-queue` enable the Debug-only `--ui-verify-throw` probe.
It requests the Simulator screen's maximum refresh rate and samples Core Animation
presentation geometry on every `CADisplayLink` callback, through 350ms after the
nominal flight. Each case saves raw `lody-throw-*.json` files and a
`throw-summary.json`: observed FPS, callback gaps, deviation from the designed
path (arc plus settle tail, recorded by the probe), backwards movement during
the flight segment, stationary interior frames, scale, and window-to-cell landing
error. Missing samples, a callback gap over 50ms, or a position discontinuity over
1.5pt fail the check. Tune the curve in `modules/lody-kit/verification/chat/throw-tuner.html`. This measures main-thread callbacks and presentation-layer
state, not GPU-presented FPS; review the accompanying framebuffer video at its
original variable frame timestamps as well. Do not upsample the movie and call
interpolated or duplicated frames additional evidence.

`--case file-preview` exercises embedded Markdown file links in chat and the
process sheet, file-type symbols and VoiceOver actions, rendered Markdown/source
switching, document-relative links, and the shared file-browser preview. It also
opens PNG/PDF through system Quick Look and checks a missing-file error. The
Debug-only `ui-verify-files` reader supplies local fixtures before the cloud
runtime; this case does not claim live Machine RPC or every Quick Look format.

The throw probe also records each presentation frame's background color. It must
start at the rendered input surface color and interpolate toward the user bubble
color; both appearances fail if the color snaps directly to its destination.
Queue fixtures inject service outcomes only; protocol checks additionally verify
real Loro movable-list updates, persist-before-watermark ordering, and no replay
after an uncertain write. They do not claim a connected-machine cloud run.
