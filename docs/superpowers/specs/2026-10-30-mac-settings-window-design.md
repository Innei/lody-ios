# Mac Settings window

Status: approved design (2026-10-30). Builder: work from this file; the TL;DR beside it is for review only.

## Intent

The Mac client's Settings is a small grid window: account, accent popup, notifications switch, a Debug button. The user wants a real Settings window that looks and behaves like macOS System Settings, organised fresh from the official Lody desktop app's Settings rather than from the iOS app, whose settings "are scattered and will be reorganised later".

Success: opening Lody › Settings (⌘,) feels like opening System Settings — a searchable sidebar with coloured icon tiles and an account card, grouped forms on the right — and every row on it does something real. The first version covers the settings people touch day to day; the heavy workspace administration pages come in a second batch.

## Goals

- A System Settings–style window: sidebar (search, account card, sections Personal / Workspace / Other) and a detail pane of grouped forms with the page title in the toolbar.
- First-version pages, each fully working: Account, General, Appearance, Keyboard, Workspace › General, Workspace › Machines, Workspace › Projects, About; Debug in Debug builds only.
- The same information architecture as the official desktop Settings, minus what a cloud-only client cannot do.

## Non-goals (this version)

- Second-batch workspace pages: Agents, Agent Roles, Memory, MCP, Prompt Shortcuts, GitHub, AI Usage, Sharing. They do not appear in the sidebar until built; no placeholder pages.
- Anything about running agents on this Mac (local agent switch, daemon, prevent sleep, terminal fonts, "Open with" launchers), Billing, default `lody://` handling, auto-update, global (system-wide) shortcuts.
- Reorganising the iOS settings.

## Anti-goals

- A settings row that looks interactive but does nothing, or a page that is mostly "coming soon".
- New macOS permission prompts beyond the existing opt-in notification request (the user must be asked before any new permission).
- Settings that silently diverge from the main window (e.g. a workspace switcher that does not move the main window).

## Constraints

- Mac client rules (AGENTS.md › Mac client): cloud client only; storage under Application Support/app.innei.lody.mac; credentials only in this Mac's Keychain; never register `lody://`.
- Accent: never green or red (AGENTS UI baseline); keep the existing `MacAccent` set (system, blue, purple, orange, graphite). Do not adopt iOS `LodyAccentChoice` (custom hex) on the Mac.
- Strings in `packages/LodyMacKit/Sources/Resources/Localizable.xcstrings` (`bundle: .lodyMac`), English and zh-Hans; `pnpm i18n:check` passes.
- Zero-comment code style, no nested ternaries, files under 500 lines (see AGENTS.md / repo rules).
- UI verification must never take the user's foreground: fast checks run `pnpm verify:mac --in-process`; real-screen checks run XCUITest in the Tart VM (`pnpm verify:mac:vm`, being built in parallel by another task). Never run UI automation on the host desktop.

## Decisions

Decided in the planning doc https://claude.ai/artifact/75msUanpByd6R47jttBxu2 (round 1, all recommendations accepted by the user) and on the canvas https://claude.ai/artifact/RbGhsRbaPLone1qTbRtVwx (round 1, all recommendations accepted).

### Navigation (doc item 1)

- Top: account card (avatar, name, "Lody account") → Account page.
- Personal: General, Appearance, Keyboard.
- Workspace (section header shows the current workspace with a switcher): General, Machines, Projects. Second batch adds Agents, Agent Roles, Memory, MCP, Prompt Shortcuts, GitHub, AI Usage, Sharing in the desktop app's order.
- Other: About. Debug (Debug builds only) after About.

### Look (canvas round 1)

- q1 → A: sidebar rows carry coloured rounded-square icon tiles with white SF Symbols, like System Settings. Tiles: General gray (`gearshape`), Appearance near-black (`circle.lefthalf.filled`), Keyboard gray (`keyboard`), Workspace General blue (`building.2`), Machines indigo (`desktopcomputer`), Projects orange (`folder`), About gray (`info.circle`), Debug gray (`hammer`). Selection is the neutral grey of the main sidebar (existing q4-a rule), not accent-filled. Board: `Main.dc.html` on the canvas.
- q2 → A: the Account page opens with a large centred avatar (72 pt), name and email, then grouped rows. Board: `Q2-A.dc.html`.
- q3 → A: Appearance shows theme as three thumbnails (Follow System / Light / Dark) and accent as a row of colour dots with the selected one ringed. Board: `Q3-A.dc.html`.
- Detail pane: grouped form sections (rounded white groups on the window background), toolbar title = page name, System Settings–style back/forward arrows are optional (builder's call).

### Technology (doc item 3)

SwiftUI for the whole Settings content: `NavigationSplitView` with a `List` sidebar and `Form { Section }` with `.formStyle(.grouped)` pages, hosted in the existing AppKit settings window through `NSHostingController`. The main window stays AppKit.

### Workspace switching (doc item 4)

The Workspace section header carries a menu of the account's workspaces (`AuthSession` account `workspaces`). Choosing one calls `CatalogSession.shared.selectWorkspace(_:)` — the same state the main sidebar's workspace popup uses — so Settings and the main window always agree. Hidden when the account has one workspace.

### Search (doc item 5)

Like System Settings: the sidebar search filters pages by page title and by the labels of the rows inside each page; matching pages stay in the list. Each page declares its searchable labels (a static index), localised.

### Mac-only items (doc item 6)

Add "Open Lody at login" (General) using `SMAppService.mainApp` register/unregister. It needs no TCC permission; macOS shows its own "Login item added" notice. Menu-bar extra, global shortcuts and auto-update are out of scope.

### Local-only appearance (doc item 7)

Theme and conversation text options apply to Lody's windows only and are stored per Mac (UserDefaults), not synced. Theme default: Follow System.

## Pages (first version)

Every row below has a working data source today unless marked "build". Rows the backend cannot support yet are left out (see "Deferred rows").

### Account

- Header: avatar (`AuthAccount.user.image`, initials fallback), name, email (`AuthAccount.user`, read-only).
- Machines you own: the workspace machine list (Machines page source) filtered to rows with `readOnly == false` — for kind `machine` the runtime sets `readOnly` to "not owned by the signed-in user" (`packages/cloud-runtime/src/runtime/settings.ts`) — with online state from catalog presence (`SettingsMachinePresence`).
- Sign out… (red text button, confirmation alert, then `AuthSession.logout()`).
- Signed-out state: the page shows a Sign In button that opens the existing sign-in flow; workspace pages are hidden.

### General

- Conversations › "While the agent is busy, messages you send": segmented Queue / Steer, bound to `LodyPreferences.queuedMessageBehavior` / `saveQueuedMessageBehavior` (`"queue"` / `"guide"`); observe `.lodyPreferencesDidChange`. This already drives `OutboxForeground`.
- Notifications › "Desktop notifications" switch with its detail line — the existing `MacNotifier.setEnabled` (opt-in authorization on first enable; unchanged behaviour).
- Startup › "Open Lody at login" switch — build: a small injectable wrapper over `SMAppService.mainApp` (status, register, unregister); reflect `.requiresApproval` by showing a hint that opens System Settings › Login Items.

### Appearance

- Theme thumbnails: Follow System / Light / Dark — build: persisted per Mac, applied as `NSApp.appearance` (nil / aqua / darkAqua) at launch and on change. Must not interfere with the Debug verify route that sets `NSApp.appearance` for catalog scenes.
- Accent dots: `MacAccent.allCases` (system shown as a multicolour dot), `MacAccent.apply()`.
- Conversation › text size slider (e.g. 11–18 pt, default 13) — build: per-Mac preference read by the transcript (markdown/prose and user bubbles) and the composer input; live update via a Mac notification.
- Conversation › "Fill window width" switch — build: per-Mac preference that lifts the transcript's max content width.

### Keyboard

Read-only list of the app's shortcuts grouped by menu, generated by walking `NSApp.mainMenu` (title + key equivalent + modifiers) so it never drifts from the real menus. Editing shortcuts is out of scope.

### Workspace › General

- Workspace name (editable) and icon (editable): `AuthSession.updateWorkspace(id:name:)` and `updateWorkspaceIcon(id:file:)`; icon chosen with `NSOpenPanel` (images). Only shown editable to members allowed to edit (if the role is unknown, read-only).
- Members (read-only list: name, email, role) — build: a new page path in `WorkspaceSettingsCloud`'s allowlist that calls `/organization/get-full-organization` and returns members plus the caller's role (today that call runs only for the GitHub page and keeps just the role). The caller's role also decides whether name and icon are editable.

### Workspace › Machines

- List of workspace machines with online state: `RuntimeContract.Calls.RemoteSettings` kind `machine` via `DataRuntime.settingsCall`, presence from `CatalogSession` snapshot. Fetched when the page opens (cache per user/workspace like iOS `SavedRemoteSettings`), with a refresh button.
- Rename (owner only; the call's `edit` action).

### Workspace › Projects

- Projects grouped by machine (`SettingsCatalog.projects` / `machineNames`).
- "Share with team" toggle per project for owners: `WorkspaceSettingsCloud` `page:"projects"` `list`/`set` (Convex `localProjects:setLocalProjectSharedWithTeam`), as iOS `ProjectVisibilityController` does.

### About

- App icon, name, version and build (`Bundle.main`).
- Open-source licenses: a Mac-specific list. `project.yml` currently copies the iOS `LodyLicenses.json` ("Lody for iOS") into the Mac app, which credits components the Mac does not ship (libdatachannel, libjuice, usrsctp, Mbed TLS, plog, Lexical iOS, Beautiful Mermaid, ElkSwift). Teach `scripts/build-licenses.mjs` a Mac dependency set and output, bundle that file instead, and show it in a sheet or sub-page; move the JSON decoder from LodyiOSKit `LodyLicenses.swift` into LodyData so both apps share it. (Builder-check call: correct attribution over reuse.)
- Diagnostics: count since launch, "Export…" (`DiagnosticsStore.export(since:)` → `NSSavePanel`), "Clear" (`clear()`).

### Debug (Debug builds only)

Embeds or links to the existing `MacDebugController` page. Stays inside `#if DEBUG` like the rest of `Sources/Debug`.

## Deferred rows (no backend support yet)

Edit display name, sign-in method, CLI token, password, "show code-only line changes", inline math, code ligatures, members invite/role change/remove, pending invitations, leave/delete workspace, machine share/revoke/remove, per-project worktree scripts/skills/MCP, delete project. They return with the APIs (better-auth `/update-user`, `/change-password`, `/list-accounts`, organization plugin endpoints) in a later pass.

## State and wiring

- One `@MainActor` observable settings model fed by `SettingsSource.live` (account, current workspace, connection) plus `.lodyAuthDidChange`, `.lodyCatalogDidChange`, `.lodyPreferencesDidChange`, `.lodyMacAccentDidChange`. Pages read the model; I/O goes through injected closures so tests and the offline catalog scene can script outcomes (pattern: `MacComposerService`, `MacSessionsSource`).
- Remember the last selected page per Mac (UserDefaults key under `lody.mac.settings.*`); ⌘, opens Settings on it.
- `MacSettingsController` is replaced; `MacMainMenu` and the app delegate keep opening Settings the same way.

## Verification

- Unit tests (LodyMacKit, TDD): search index matching, theme persistence/apply, login-item wrapper states, queued-behaviour binding, last-page restore, workspace switch calls `selectWorkspace`, members decoding, licenses decoding (LodyData), keyboard list built from a menu.
- Offline Debug catalog scene `settings` (and keep `accent`) built from production views with scripted services; deep link `lodymacverify://case/settings`.
- In-process verify: SwiftUI controls are not `NSControl`s, so extend the Debug dump and `act` routes to read and press through the accessibility tree for hosting views (identifiers via `.accessibilityIdentifier`). Update the `accent` case to the colour dots and add a `settings` case (navigate pages, switch theme, queue/steer).
- Real-screen: the VM XCUITest harness and suite belong to the parallel VM task (`verification/mac/UITests`, `pnpm verify:mac:vm`). This work gives every page and control a stable accessibility identifier (`settings-<page>` for sidebar rows, `settings-<page>-<control>` for controls) and lists them in `verification/mac/README` or the UITests folder's notes. "Done" for this spec = unit tests + the in-process `settings`/`accent` cases green; once the VM runner exists, add the Settings XCUITest flows there as a follow-up. Never run UI automation on the host.

## Left to the builder

Exact SwiftUI composition and file split; whether to keep System Settings back/forward arrows; text-size range and step; how members/roles are decoded; licenses presentation (sheet vs sub-page); icon tile sizes; how the Debug page is embedded.

## Artifacts

- Planning doc (Claude Doc): https://claude.ai/artifact/75msUanpByd6R47jttBxu2 — navigation, scope, SwiftUI, workspace switcher, search, login item, local-only appearance.
- Design canvas: https://claude.ai/artifact/RbGhsRbaPLone1qTbRtVwx — boards `Main.dc.html` (q1 A colour tiles), `Q2-A.dc.html` (account header), `Q3-A.dc.html` (appearance thumbnails + dots); components `Sidebar.dc.html`, `General.dc.html`.
- Upstream reference: `~/git/fork/Lody` `upstream/main` `packages/components/src/components/settings/desktop-settings-modal.tsx` and siblings.
