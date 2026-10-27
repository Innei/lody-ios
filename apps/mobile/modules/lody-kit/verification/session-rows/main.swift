import Foundation

let hour = 3_600_000.0
let now = Date().timeIntervalSince1970 * 1000

let saved = """
{"catalog":{"projects":[{"id":"p","name":"Lody","rootPath":"/Users/me/lody","machineId":"m"},{"broken":true}],
"machineIds":["m"],"sessions":[
{"id":"root","title":"Root","status":"completed","archived":true,"pinned":false,"projectId":"p","createdAt":"2026-01-02T03:04:05.678Z","lastMessageAt":\(now - 120_000),"lastReadAt":\(now - hour),"branchName":"main","lastModel":{"name":"","modelId":"gpt-5"},"diff":{"add":3,"del":1}},
{"id":"child","title":"Child","status":"error","archived":true,"pinned":false,"projectId":"p","createdAt":"2026-01-02T03:04:05Z","openedBySessionId":"root","lastModel":null},
{"id":"tab","title":"Tab","status":"running","archived":true,"pinned":false,"projectId":"p","createdAt":"2026-01-02T03:04:05Z","parentSessionId":"root"},
{"id":"chat","title":"Chat","status":"waiting","archived":false,"pinned":true,"projectId":"w:unassigned","createdAt":"2026-01-02T03:04:05Z","awaitingUserSince":1,"branchName":""},
{"title":"missing id"}
]}}
"""
guard let catalog = SessionCatalog.decode(saved: Data(saved.utf8)) else { fatalError("Catalog must decode") }
precondition(catalog.projects.map(\.id) == ["p"], "Malformed projects are dropped")
precondition(catalog.machineIds == ["m"] && catalog.machineNames.isEmpty)
precondition(catalog.sessions.map(\.id) == ["root", "child", "tab", "chat"], "Malformed sessions are dropped")
precondition(SessionCatalog.decode(saved: Data(#"{"catalog":{"projects":[],"sessions":[]}}"#.utf8)) == nil, "Incomplete catalogs are rejected")

let root = catalog.sessions[0], child = catalog.sessions[1], tab = catalog.sessions[2], chat = catalog.sessions[3]
precondition(child.modelNeverRan && !root.modelNeverRan && root.modelName == "gpt-5")
precondition(chat.branchName == nil, "Empty branch names behave like JS falsy values")
precondition(child.activityAt == 1_767_323_045_000 && root.lastMessageAt == root.activityAt)

precondition(SessionState(root) == .archived && SessionState(chat) == .attention)
var live = chat
live.status = "running"
precondition(SessionState(live) == .live, "Awaiting input never hides a live run")

let row = SessionRows.row(root, projectName: "Lody", now: now)
precondition(row.subtitle == "Lody · main" && row.subtitleMono && row.modelName == "gpt-5")
precondition(row.value == "time.minutesAgo" && row.unread && row.badge == "inbox.badge.archived" && row.imageTint.isEmpty)
precondition(row.actions.map(\.id) == ["read", "archive"] && row.actions[1].title == "session.action.unarchive")
precondition(row.leadingActions.map(\.id) == ["pin"] && row.leadingActions[0].tint == "yellow")
precondition(row.menuActions.map(\.id) == ["rename", "pin", "archive", "share", "delete"] && row.menuActions[4].destructive)
precondition(row.preview == "session" && row.navigates && row.action && row.diff == ["add": 3, "del": 1])
precondition(SessionRows.row(child).modelName == "session.notRun")
var viewed = root
viewed.lastViewedMessageAt = root.lastMessageAt
precondition(!SessionRows.row(viewed).unread && SessionRows.isUnread(viewed), "A local view clears emphasis, not the read action")
let chatRow = SessionRows.row(chat)
precondition(chatRow.badge == "inbox.badge.attention" && chatRow.imageTint == "warning" && chatRow.subtitle.isEmpty)

let archived = catalog.sessions.filter(\.archived).sorted(by: SessionRows.byActivity)
precondition(archived.map(\.id) == ["root", "child", "tab"])
let rows = SessionRows.treeRows(archived, all: catalog.sessions) { SessionRows.row($0, now: now) }
precondition(rows.map(\.id) == ["root", "child", "tab"], "Opened sessions nest; contained tabs keep their own entry")
precondition(rows[0].collapsedValue == "inbox.session.children" && rows[1].parentId == "root" && rows[2].parentId.isEmpty)
precondition(rows[0].collapsedBadge == "inbox.badge.archived")
precondition(SessionRows.treeRows(archived, all: catalog.sessions, maxRoots: 1) { SessionRows.row($0) }.count == 2)

var cycleA = SessionItem(id: "a", projectId: "p", openedBySessionId: "b")
var cycleB = SessionItem(id: "b", projectId: "p", openedBySessionId: "a")
cycleA.lastMessageAt = 2
cycleB.lastMessageAt = 1
precondition(SessionRows.tree([cycleA, cycleB], all: [cycleA, cycleB]).count == 2, "Opener cycles terminate as separate entries")
precondition(SessionRows.tree([cycleA], all: [cycleA, cycleB]).count == 1, "Hidden openers do not group")

var pinned = SessionItem(id: "pinned", pinned: true, lastMessageAt: 1)
let recent = SessionItem(id: "recent", lastMessageAt: 5)
precondition([recent, pinned].sorted(by: SessionRows.byActivity).map(\.id) == ["pinned", "recent"])
pinned.pinned = false
precondition([pinned, recent].sorted(by: SessionRows.byActivity).map(\.id) == ["recent", "pinned"])

precondition(SessionRows.deletionTargets(catalog.sessions, id: "root").map(\.id) == ["root", "tab"])
precondition(!SessionRows.deletionBlocked([root, child]) && SessionRows.deletionBlocked([live]))
precondition(SessionRows.projectId(ofRow: "toggle:p") == "p" && SessionRows.projectId(ofRow: "project:p") == "p")
precondition(["chat", "toggle:pinned", "view:x", "root"].allSatisfy { SessionRows.projectId(ofRow: $0) == nil })
precondition(SessionRows.projectMenu(SessionProject(id: "p", rootPath: "/x")).map(\.id) == ["newSession", "open", "copyPath"])
precondition(SessionRows.projectMenu(SessionProject(id: "w:unassigned")).map(\.id) == ["open"])

let views = catalog.viewed(["root": root.lastMessageAt!])
precondition(views.sessions[0].lastViewedMessageAt == root.lastMessageAt && views.sessions[1].lastViewedMessageAt == nil)

let day = 86_400_000.0
let midday = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: now / 1000)).timeIntervalSince1970 * 1000 + 12 * hour
func item(_ id: String, _ status: String = "completed", project: String = "p", at: Double = midday, _ change: (inout SessionItem) -> Void = { _ in }) -> SessionItem {
  var session = SessionItem(id: id, title: id, status: status, projectId: project, lastMessageAt: at, lastReadAt: at)
  change(&session)
  return session
}
let inboxCatalog = SessionCatalog(projects: [SessionProject(id: "p", name: "lody-ios")], sessions: [
  item("waiting", "waiting"), item("failed", "error"), item("running", "running"),
  item("unread") { $0.lastReadAt = midday - hour }, item("pinned") { $0.pinned = true },
  item("today"), item("yesterday", at: midday - day), item("week", at: midday - 3 * day), item("month", at: midday - 20 * day),
  item("older", at: midday - 60 * day), item("archived") { $0.archived = true },
])
let inbox = InboxSections.inbox(inboxCatalog, now: midday)
precondition(inbox.map(\.id) == ["attention", "pinned", "live", "unread", "today", "yesterday", "week", "month", "older"], "\(inbox.map(\.id))")
precondition(inbox[0].rows.map(\.id) == ["waiting", "failed"] && inbox[0].header == "inbox.section.attention")
precondition(!inbox.flatMap(\.rows).contains { $0.id == "archived" }, "Archived sessions stay out until searched")
precondition(InboxSections.inbox(inboxCatalog, keyword: "archived", now: midday).flatMap(\.rows).map(\.id) == ["archived"])
precondition(inbox[2].rows[0].imageTint == "blue" && inbox[4].rows[0].imageTint.isEmpty && inbox[0].rows[1].imageTint == "danger")
precondition(inbox[0].rows[0].subtitle == "lody-ios" && inbox.flatMap(\.rows).allSatisfy { $0.diff.isEmpty })
precondition(InboxSections.inbox(inboxCatalog, chatOnly: true, now: midday).isEmpty)

let many = SessionCatalog(projects: [SessionProject(id: "p", name: "lody-ios", rootPath: "/Users/me/git/lody-ios"), SessionProject(id: "empty", name: "Empty")],
  sessions: (0..<6).map { item("s\($0)", at: midday - Double($0) * hour) } + [item("c1", project: "m:unassigned"), item("pin") { $0.pinned = true }])
let projects = InboxSections.projects(many, now: midday)
precondition(projects.map(\.id) == ["pinned", "empty", "p", "chat"], "\(projects.map(\.id))")
precondition(projects[0].rows.map(\.id) == ["toggle:pinned", "pin"] && projects[0].headerExpanded == true)
precondition(projects[1].rows[0].id == "project:empty" && projects[1].rows[0].badge == "0" && projects[1].rows[0].navigates)
let lody = projects[2]
precondition(lody.rows[0].id == "toggle:p" && lody.rows[0].subtitle == "~/git/lody-ios" && lody.rows[0].monogram == "l")
precondition(lody.rows.dropFirst().map(\.id) == ["s0", "s1", "s2", "s3", "s4", "project:p"] && lody.rows.last?.title == "inbox.project.more")
precondition(projects[3].rows.map(\.id) == ["toggle:chat", "c1"] && projects[3].rows[0].menuActions.map(\.id) == ["newChat"])
let collapsed = InboxSections.projects(many, expanded: ["p": false], now: midday)[2]
precondition(collapsed.headerExpanded == false && collapsed.rows[0].badge == "6" && collapsed.rows.count == lody.rows.count)

var urgent = many
urgent.projects.append(SessionProject(id: "z", name: "zeta"))
urgent.sessions.append(item("z1", "waiting", project: "z", at: midday - 90 * day))
precondition(InboxSections.projects(urgent, sort: .urgency, now: midday).map(\.id) == ["pinned", "z", "p", "empty", "chat"])
precondition(InboxSections.projects(urgent, sort: .activity, now: midday).map(\.id) == ["pinned", "p", "z", "empty", "chat"])
let zetaParent = InboxSections.projects(urgent, now: midday).first { $0.id == "z" }!.rows[0]
precondition(zetaParent.value == "inbox.project.attention" && zetaParent.imageTint == "warning")

precondition(InboxSections.reconcilePinOrder(["b", "gone", "a"], pinned: ["a", "b", "c", "d"]) { ["c": 1, "d": 2][$0] ?? 0 } == ["d", "c", "b", "a"])
precondition(InboxSections.orderPinned([item("x") { $0.pinned = true }, item("y", at: midday + 1) { $0.pinned = true }], pinOrder: ["x"]).map(\.id) == ["x", "y"])

let hits = InboxSections.match(many, keyword: "LODY")
precondition(hits.projectIds == ["p"] && hits.sessions.count == 7)
let found = InboxSections.search(many, hits: InboxSearchHits(projectIds: ["p"], sessions: [("s1", "matched line"), ("s2", nil)]), now: midday)
precondition(found.map(\.id) == ["projects", "sessions"] && found[0].rows[0].id == "project:p" && found[0].rows[0].menuActions.count == 3)
precondition(found[1].rows.map(\.id) == ["s1", "s2"] && found[1].rows[0].subtitle == "matched line" && found[1].rows[1].subtitle == "lody-ios")
precondition(InboxSections.search(many, hits: InboxSearchHits()).isEmpty)
precondition(InboxSections.activityBucket(.nan, now: midday) == "today" && InboxSections.activityBucket(midday - 8 * day, now: midday) == "month")
let entry: [String: Any] = [
  "fileDiffs": [["path": "a.swift", "add": 2, "del": 1]],
  "items": [
    ["type": "tool_call", "kind": "edit", "path": "a.swift", "added": 9, "removed": 9],
    ["type": "tool_call", "kind": "read", "path": "r.swift", "added": 1],
    ["type": "tool_call", "kind": "write", "path": "n.swift", "added": 4],
    ["type": "tool_call", "kind": "edit", "path": "n.swift", "added": 1, "removed": 2],
    ["type": "tool_call", "kind": "delete", "path": "n.swift"],
    ["type": "tool_call", "kind": "edit", "path": ""],
    ["type": "text", "path": "t.swift"],
  ],
]
let files = SessionEnvelope.changedFiles(entry)
precondition(files.map { $0["path"] as? String } == ["a.swift", "n.swift"], "Recorded diffs win; reads, empty paths and non-tools are skipped")
precondition(files[0]["add"] as? Int == 2 && files[0]["status"] as? String == "M")
precondition(files[1]["add"] as? Int == 5 && files[1]["del"] as? Int == 2 && files[1]["status"] as? String == "D")
let envelope = SessionEnvelope.prepare(#"{"v":1,"status":"live","revision":4,"preview":{"label":"localhost:5173","active":true},"entries":[{"id":"e","items":[]}]}"#)!
precondition(envelope.revision == 4 && envelope.entriesJSON.contains(#""fileDiffs":[]"#))
precondition(SessionEnvelope.prepare("not json") == nil && SessionEnvelope.prepare(#"{"v":1,"overflow":true}"#)!.overflow)
precondition(envelope.accepted(generation: 0, after: (-1, -1)), "A newer runtime generation resets the cursor")
precondition(!envelope.accepted(generation: 0, after: (1, -1)), "Older generations drop")
precondition(!envelope.accepted(generation: 1, after: (1, 4)) && envelope.accepted(generation: 1, after: (1, 3)), "Same generation needs a newer revision")
precondition(!SessionEnvelope(version: 2, revision: 9).accepted(generation: 5, after: (1, 1)), "Unknown envelope versions drop")
print("PASS: session rows, inbox sections and session envelopes match the RN projections")

let toolsCatalog = SessionCatalog.decode(saved: Data(#"{"catalog":{"projects":[],"machineIds":["mac"],"machineSimulators":{"mac":"available"},"sessions":[{"id":"with-tools","pullRequests":[{"repository":"Innei/lody-ios","number":31,"status":"open","ci":"f"}],"iosSimulatorPreviewRequestId":"preview-request"}]}}"#.utf8))!
precondition(toolsCatalog.machineSimulators["mac"] == "available")
precondition(toolsCatalog.session("with-tools")?.pullRequests.first?.number == 31)
precondition(toolsCatalog.session("with-tools")?.iosSimulatorPreviewRequestId == "preview-request")

precondition(envelope.preview == SessionBrowserPreview(label: "localhost:5173", active: true))
