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
print("PASS: session rows match the RN inbox projection")
