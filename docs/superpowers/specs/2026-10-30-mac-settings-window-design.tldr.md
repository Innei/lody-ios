# Mac Settings window — TL;DR

**What gets built:** a System Settings–style window (⌘,): searchable sidebar with colour icon tiles and an account card on the left, grouped forms on the right. Built in SwiftUI inside the existing AppKit window.

**What you'll see**

1. Press ⌘, → Settings opens on the last page you used.
2. Sidebar: account card, then 个人 (通用 / 外观 / 键盘), 工作区 (通用 / 机器 / 项目, with a workspace switcher in the header), 其他 (关于).
3. Search matches page names and the row labels inside pages.
4. 账户: big avatar, name, email, your machines with online state, Sign out (with confirmation).
5. 通用: queue vs steer for messages sent while the agent is busy, desktop notifications, open Lody at login.
6. 外观: theme thumbnails (system / light / dark), accent dots, conversation text size, fill window width.
7. 键盘: read-only list of every menu shortcut.
8. 工作区: rename and re-icon the workspace, read-only member list, machines (rename yours), projects (share with team).
9. 关于: version, Mac-specific open-source licenses, diagnostics export and clear.

**Decisions**

| Item | Decision | Whose |
|---|---|---|
| Structure | Follows the official desktop app; drops local-agent items and Billing | yours (doc round 1) |
| Look | Colour tiles; large account header; theme thumbnails + dots | yours (canvas round 1) |
| Tech | SwiftUI `NavigationSplitView` + `Form(.grouped)` | yours (doc round 1) |
| First version | 8 pages; agents / roles / memory / MCP / prompts / GitHub / usage / sharing come later | yours (doc round 1) |
| Appearance | Stored on this Mac only | yours (doc round 1) |

**Check these (my calls)**

- Rows with no backend support are left out: editing your name, password, CLI token, invitations, member roles, leave/delete workspace, machine revoke, project delete or scripts, inline math, ligatures.
- Text size and full width are kept (new Mac-only work).
- Members are read-only. Showing them needs one new cloud path.
- Licenses: a correct Mac-only list, not the iOS one, which credits libraries the Mac app doesn't ship.
- In-process verify gets accessibility-tree support so it can see SwiftUI controls. The VM XCUITest flows for Settings are added once the VM runner exists.

**Time:** about one working day of agent time (≈ 6–8 h): window shell and search ~1.5 h, personal pages ~2 h, workspace pages ~2 h, About and licenses ~1 h, verification hooks ~1.5 h.
