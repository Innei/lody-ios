# macOS AppKit client

Decided with the user in the [Lody macOS AppKit target](https://claude.ai/artifact/U6TYtbhFe2S1WWiCHsvoCf)
doc (rounds 1–2) and on the [Lody Mac design language](https://claude.ai/artifact/3LSmrnU2B8LPdJ89dSTdCh)
canvas (rounds 1–3), 2026-10-30.

## Intent

The official Lody desktop app is Electron and feels heavy. The user wants a
native Mac client that feels like a real Mac app. The iOS client is already
pure UIKit, and most of its data layer does not touch UIKit, so the Mac client
reuses the protocol, data runtime and session state and rewrites only the UI in
AppKit, as a new target in this repository.

## Goals

- A Lody Cloud client on macOS, same role as iOS: sign in, browse workspaces and
  sessions, read transcripts, send text turns, answer permission requests.
- One shared data layer (`LodyData`) used by both the iOS and Mac apps.
- Keep syncing while the window is closed; post local notifications when an
  agent needs approval or finishes a reply.

## Non-goals (v1)

- Running agents locally or acting as a machine. The official desktop app or
  CLI keeps that role.
- Diff pages, attachments, the rich-text (Lexical) composer, remote push
  (OneSignal), Share, workspace settings sub-pages, Live Activity.
- Menu bar residency, auto-update (Sparkle comes after v1 is stable), Mac App Store.

## Anti-goals

- A Catalyst / Designed-for-iPad look, or UIKit idioms painted onto AppKit.
- A second protocol or data-runtime implementation for Mac.
- Any user-visible iOS behavior change caused by the extraction.
- Copying the desktop app's structure. It is a reference only.

## Constraints

- Everything in `AGENTS.md` still holds for shared code: signing stays enabled,
  credentials live only in Keychain, no remote scripts in the WebView, the
  host↔runtime boundary is the versioned contract in `packages/cloud-runtime/src/contract`,
  no second live replica, writes are never replayed across runtime recovery.
- Minimum macOS 26 and iOS 26, Swift 6 language mode.
- Other sessions commit to `main` concurrently. Stage only your own files.
- Never edit generated Xcode projects; targets go in `project.yml` (at `apps/ios/` until phase 2 moves it to the
  repository root).

## Package layout

| Package | Platforms | Contents |
| --- | --- | --- |
| `packages/lody-core` | iOS 26, macOS 26 (already) | unchanged |
| `packages/LodyData` (new) | iOS 26, macOS 26 | shared data layer, see below |
| `packages/LodyKit` → `LodyiOSKit` | iOS 26 | iOS UI, controllers, iOS-only services |
| `packages/LodyMacKit` (new) | macOS 26 | AppKit UI and Mac-only services |

### What moves into `LodyData`

| Moves | Stays in the iOS package |
| --- | --- |
| Auth: `AuthAPI`, `AuthKeychain`, `AuthSession` | LiveActivity |
| Catalog (all) | Notifications (OneSignal, push click buffer) |
| Cloud data: `DataRuntime` and its extensions, `LocalStore`, `ContentStore`, `FlockDecoder`, workspace / GitHub / sharing cloud calls, `RuntimeJSON` | `ShareStore` |
| Outbox: store, dispatcher, record, `OutboxSession` | `*Sections` list-row descriptions (move later when Mac needs them) |
| CreateSession data: `CreateSessionService`, `CreateModelOptions`, `CreateSessionForm`, `CreateDraftRecord` | `CreateSessionController` and its pages |
| Sessions models: source, sender, feed, envelope, catalog, permission projection/service, decisions, composer model | All controllers and views |
| Preferences, Diagnostics store, Text utilities | |
| Transcript projection: `Chat/ChatTranscript.swift` and `ChatStream`; `chat-kit`'s `ChatKitCore` gains a macOS platform | |

The Mac renders the same transcript rows as iOS (tool calls, plans, subagent
cards, permission requests), so it must use the shared projection rather than
derive its own.

The window opens sessions in native window tabs (see Mac app below). `DataRuntime` keeps a
single current session and `PermissionSource` depends on it, so v1 keeps the
contract: only the frontmost tab streams its transcript. Background tabs show
live status (working, needs approval, done) from the workspace catalog, which
already covers every session, and resume streaming when brought to front.
Several streaming transcripts at once would need a runtime contract change and
are out of scope.

Move files in small batches, one directory at a time, each landing on `main`
separately, so concurrent sessions editing LodyKit are not broken by one large
move.

A file moves only if it compiles for macOS after its UIKit ties are replaced by
the host seam below; anything else stays and is listed in the extraction PR.

### Rename and repository layout

After the extraction lands, two mechanical commits, each on its own:

1. Rename `LodyKit` to `LodyiOSKit`: package directory and product, the single
   `import LodyKit` in the app, `project.yml` (including Share Extension source
   paths), scripts and `AGENTS.md`.
2. Make the repository root the Xcode project root and remove `apps/`:

```
project.yml → Lody.xcodeproj    iOS app, extensions and macOS app targets
iOS/                            was apps/ios/App
macOS/                          new: Mac app entry, Info.plist, entitlements
Extensions/                     was apps/ios/Extensions (iOS only)
packages/                       Swift packages and cloud-runtime, unchanged
runtime/ scripts/ tests/ verification/   were under apps/ios/
package.json                    absorbs @lody-ios/ios dependencies and scripts
```

`pnpm-workspace.yaml` keeps only `packages/*`; root scripts lose their
`--filter @lody-ios/ios`. Every `apps/ios` path changes: CI workflows,
`package.json`, verification and build scripts, `.gitignore`, `.prettierignore`,
README and `AGENTS.md`. Run the pnpm install once, explicitly, before any build
(a dependency move otherwise triggers an install inside `pnpm <script>`).
The repository name and `@lody-ios/*` package names stay. Land the move when
no other session has open edits under `apps/ios`. Historical specs and plans
keep the old paths.

## Host seam

`LodyData` must not import UIKit or AppKit. The known ties today:

| Where | Tie |
| --- | --- |
| `DataRuntime.swift` | `UIApplication` did-enter-background / did-become-active / memory-warning notifications, `applicationState` |
| `SessionBackgroundTasks.swift` | `beginBackgroundTask` / `endBackgroundTask` for user-started sends |
| `OutboxSession.swift:178` | `connectedScenes` lookup |
| `DataRuntime+HostCalls.swift:67` | `UIApplication.shared.open(url)` |
| `AuthSession.swift` | `UIViewController` for presenting sign-in |

`AuthSession` also reaches into iOS-only services on sign-out (`ShareStore`,
push, Live Activities, the logout toast), and `OutboxSession` presents a
`UIWindow` alert. These become host hooks too.

Each app injects one host object at launch that provides: lifecycle events
(active, background, memory pressure) and the current state; open URL; a short
background allowance for user-started sends (no-op on Mac); sign-out cleanup
hooks; failure alerts; and a present/dismiss pair for the Device Flow
authorization page. iOS keeps presenting it in `SFSafariViewController`
exactly as today (no move to `ASWebAuthenticationSession`); the Mac opens the
default browser with `NSWorkspace` and shows the user code in its own window.
The existing iOS behavior — background suspension retains the WebView and resets
its heartbeat on foreground, sends use only a short `UIApplication` allowance —
is reproduced exactly by the iOS host.

On Mac, "background" means the app is not frontmost; the runtime keeps running
and syncing. Closing the last window does not quit the app.

State observation stays as today: `AuthSession`, `CatalogSession` and
`OutboxSession` post NotificationCenter projections, and Mac controllers observe
the same notifications. Moving to Observation is out of scope and would be done
on both platforms together.

### Resources and localization

- The data runtime and `FlockDecoder` load generated assets from `Bundle.main`.
  The Mac app target must bundle the same generated runtime resources (and their
  licenses) as the iOS app.
- Strings used by `LodyData` (errors, status text) move to a `LodyData`
  `Localizable.xcstrings` with its own bundle accessor. Mac UI strings live in
  `LodyMacKit`. Languages stay en + zh-Hans. `pnpm i18n:check` and
  `pnpm native:sources` must cover the new packages.

## Mac app (v1)

- New macOS application target in the root `project.yml`, sources in `macOS/`, product name
  “Lody” (the user's call, although the official desktop app uses the same
  name on the same Mac), bundle id `app.innei.lody.mac`, depending on `LodyData` and `LodyMacKit`.
- New sessions: machine, project, agent and model pickers backed by the shared
  CreateSession data layer; text-only first turn (attachments are a non-goal).
- Device Flow sign-in with the currently registered `lody-cli` client, as on iOS.
  Credentials go in the Mac's own Keychain; no sharing with iOS, no iCloud
  Keychain sync.
- Screens: sign-in, a sidebar with workspaces and sessions, sessions open in
  tabs, a session transcript rendered with MarkdownView/Litext (both have
  AppKit implementations), a plain-text composer, permission approval.
## Mac visual design

Chosen boards on the [design canvas](https://claude.ai/artifact/3LSmrnU2B8LPdJ89dSTdCh):
q1-c (sidebar + session tabs), q2-a (macOS 26 system defaults: Liquid Glass
floating sidebar, unified toolbar, 13 pt system text) with the Codex desktop
app as reference, q3-a, q4-a, q8-a/q8-b. The boards are the visual reference;
the rules below win where they differ.

- Transcript (q3-a): the iOS quiet document flow. Only assistant prose is at
  full contrast; user turns are a grey rounded block on the trailing side; tool
  calls are grey single lines with an icon; diff counts use systemGreen /
  systemRed; the permission request is the only card.
- Sidebar (q4-a), following Codex: New Session / Search / Needs Approval
  at the top, collapsible project groups with their sessions, Pinned above
  them, account and machine status at the bottom; neutral grey selection.
- Accent: primary actions (Send, Allow) use the accent. It follows the macOS
  system accent by default, and Settings offers a custom accent (blue, purple,
  pink, orange, graphite). Green and red are not offered because diff
  additions and deletions/destructive actions use them.
- Tabs are native window tabs (`NSWindow` tabbing): ⌘T, drag a tab out into
  its own window, merge from the Window menu; each tab keeps its own sidebar
  state. Board q1-c drew an in-content tab strip; the native tab bar replaces it.
- Composer (q8) follows the Codex desktop composer: a context tray attached
  above the input (new session: project, machine and agent pickers; reply:
  read-only project, branch and machine), the input, then a control row with
  the permission mode on the left (“Full access” in orange as a warning) and
  model + reasoning effort and the accent-coloured send button on the right.
  No attachment or dictation buttons in v1.
- Light and dark appearance both follow the system.

## Mac behavior

- Local notifications (`UNUserNotificationCenter`) for pending permission
  requests and finished replies, while the session is not on screen. v1 covers
  the active workspace only, derived from its catalog status changes; other
  workspaces would need extra replicas.
- The Mac app does not register the `lody://` scheme in v1: the official
  desktop app already owns it on the same machine. `AppLink` routing is not
  wired on Mac.
- Distribution: Developer ID signing, notarization, `.dmg`.

## Phases

1. **Extract `LodyData`.** No UI work, no iOS behavior change. Done when the
   iOS checks below pass and `LodyData` builds and tests on macOS.
2. **Rename and flatten**: `LodyKit` → `LodyiOSKit`, then the repository root
   becomes the Xcode project root.
3. **Mac v1** following “Mac app”, “Mac visual design” and “Mac behavior”.
4. **Distribution**: notarized `.dmg`.

Estimates: phase 1 3–5 days (CreateSession data included), phase 2 about a day,
phase 3 3–4 weeks (new-session flow, tabs and custom accent included), phase 4
about a day.

## Verification

- Phases 1–2: `pnpm check`, `pnpm test`, `pnpm bundle`, `pnpm verify:native`,
  `swift test --package-path packages/lody-core`, a signed iOS Simulator build,
  and the existing UI Verify cases that touch sign-in, inbox, session and send.
  `swift build` and `swift test` for `LodyData` on macOS.
- Phase 3: the Mac target build joins `pnpm check`; `LodyData` macOS tests;
  `screencapture` screenshots of the main window (light and dark), the
  new-session composer and a permission request, compared against the chosen
  boards. Automated Mac UI verification comes after v1.

## Left to the builder

- The exact Swift shape of the host seam and where it is injected.
- Which borderline Sessions/Cloud files move, following the rule above.
- Mac app source folder and scheme names.
- Whether the Mac Keychain item uses the data-protection keychain.
- Notarization scripting.
