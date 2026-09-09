import Foundation

typealias State = LodyActivityAttributes.ContentState
typealias Item = State.Item

let decoder = JSONDecoder()

func decode(_ json: String) -> State {
  try! decoder.decode(State.self, from: Data(json.utf8))
}

func item(_ id: String, _ status: Item.Status, _ updatedAt: Double) -> Item {
  Item(
    id: id,
    status: status,
    statusLabel: status.rawValue,
    permissionRequestId: nil,
    permissionCommand: nil,
    agentLogoKind: "claude",
    agentLogoText: "CL",
    title: id,
    updatedAt: updatedAt,
    updatedAtLabel: "now"
  )
}

let full = decode("""
{
  "totalCount": 3,
  "statusCounts": { "permission": 1, "question": 1, "running": 1, "unread": 0 },
  "items": [
    {
      "id": "one",
      "status": "permission",
      "statusLabel": "Needs permission",
      "permissionRequestId": "req-1",
      "permissionCommand": "rm -rf /tmp/x",
      "agentLogoKind": "brand-new-agent",
      "agentLogoText": "BN",
      "title": "Refactor the parser",
      "updatedAt": 1757000000.5,
      "updatedAtLabel": "2m ago"
    }
  ],
  "permissionAlert": { "title": "Approve command?", "body": "rm -rf /tmp/x" }
}
""")
precondition(full.totalCount == 3)
precondition(full.statusCounts.permission == 1 && full.statusCounts.unread == 0)
precondition(full.items[0].permissionRequestId == "req-1")
precondition(full.items[0].permissionCommand == "rm -rf /tmp/x")
precondition(full.items[0].agentLogoKind == "brand-new-agent", "unknown logo kinds survive as strings")
precondition(full.items[0].updatedAt == 1757000000.5)
precondition(full.permissionAlert?.title == "Approve command?")

let minimal = decode("""
{
  "totalCount": 1,
  "statusCounts": { "running": 2 },
  "items": [
    {
      "id": "two",
      "status": "running",
      "statusLabel": "Working",
      "agentLogoKind": "codex",
      "agentLogoText": "CX",
      "title": "Build",
      "updatedAt": 1757000001,
      "updatedAtLabel": "now",
      "futureField": "ignored"
    }
  ],
  "schemaVersion": 7
}
""")
precondition(minimal.permissionAlert == nil, "missing permissionAlert is tolerated")
precondition(minimal.items[0].permissionRequestId == nil && minimal.items[0].permissionCommand == nil)
precondition(minimal.statusCounts.running == 2)
precondition(minimal.statusCounts.permission == 0 && minimal.statusCounts.question == 0 && minimal.statusCounts.unread == 0, "missing count keys default to 0")
precondition(minimal.items[0].updatedAt == 1757000001, "integer updatedAt decodes as a Double")

let tolerant = decode("""
{
  "totalCount": 0,
  "statusCounts": {},
  "items": [],
  "schemaVersion": 9,
  "extra": { "nested": true }
}
""")
precondition(tolerant.focus == nil && tolerant.others.isEmpty && tolerant.othersCount == 0)
precondition(!tolerant.isActive && !tolerant.needsAttention)
precondition(tolerant.dismissalDate(from: Date()) == nil, "no focus means nothing to dismiss")

let mixed = State(
  totalCount: 5,
  statusCounts: .init(permission: 1, question: 2, running: 1, unread: 1),
  items: [
    item("unread", .unread, 500),
    item("running", .running, 400),
    item("permission", .permission, 300),
    item("question-old", .question, 100),
    item("question-new", .question, 200),
  ],
  permissionAlert: nil
)
precondition(mixed.focus?.id == "question-new", "question outranks everything, ties break on newer updatedAt")
precondition(mixed.others.map(\.id) == ["question-old", "permission"], "others follow the same order, capped at 2")
precondition(mixed.othersCount == 4)
precondition(mixed.needsAttention && mixed.isActive)

let permissionFocus = State(
  totalCount: 2,
  statusCounts: .init(permission: 1, question: 0, running: 0, unread: 1),
  items: [item("unread", .unread, 900), item("permission", .permission, 100)],
  permissionAlert: nil
)
precondition(permissionFocus.focus?.id == "permission" && permissionFocus.needsAttention)

let idle = State(
  totalCount: 1,
  statusCounts: .init(permission: 0, question: 0, running: 0, unread: 1),
  items: [item("unread", .unread, 900)],
  permissionAlert: nil
)
precondition(!idle.isActive && !idle.needsAttention)
precondition(idle.focus?.id == "unread")
precondition(idle.othersCount == 0)

let now = Date(timeIntervalSince1970: 1_757_000_000)
precondition(idle.staleDate(from: now) == now.addingTimeInterval(1800))
precondition(idle.dismissalDate(from: now) == now.addingTimeInterval(900))
precondition(mixed.dismissalDate(from: now) == nil, "an active activity never auto-dismisses")

precondition(
  item("ms", .running, 1_700_000_000_000).updatedDate == Date(timeIntervalSince1970: 1_700_000_000),
  "updatedAt is milliseconds"
)

let route = LodyActivityAttributes.route(workspaceSlug: "my space", sessionId: "a/b c")
precondition(route.absoluteString == "lody:///my%20space/sessions/a%2Fb%20c", route.absoluteString)

print("PASS: activity payload tolerance, focus priority and tie-break, others cap, activity lifetimes, millisecond timestamps, deep-link encoding")

let catalog = LiveActivityCatalog.state(catalogJSON: """
{
  "projects": [],
  "machineIds": ["m1"],
  "sessions": [
    { "id": "run", "title": "Build the widget", "status": "running", "lastMessageAt": 1757000002000, "agentType": "codex" },
    { "id": "await", "title": "Approve force push", "status": "running", "awaitingUserSince": 1757000003000, "lastMessageAt": 1757000001000, "agentType": "claude" },
    { "id": "idle", "title": "Old thread", "status": "completed", "lastMessageAt": 1757000000000, "agentType": "claude" },
    { "id": "archived", "title": "Archived but running", "status": "running", "archived": true, "lastMessageAt": 1757000006000, "agentType": "claude" },
    { "id": "queued", "title": "Waiting to run", "status": "queued", "lastMessageAt": 1757000004000, "cliType": "gemini" },
    { "id": "nameless", "title": "No agent", "status": "pending", "lastMessageAt": 1757000005000 }
  ]
}
""")
precondition(catalog.items.map(\.id) == ["run", "await", "queued", "nameless"], "idle and archived sessions are skipped")
precondition(catalog.totalCount == 4)
precondition(catalog.statusCounts.running == 3 && catalog.statusCounts.permission == 1)
precondition(catalog.statusCounts.question == 0 && catalog.statusCounts.unread == 0)
precondition(catalog.isActive && catalog.needsAttention)
precondition(catalog.focus?.id == "await", "awaiting sessions outrank running ones")
precondition(catalog.items[1].status == .permission, "awaitingUserSince wins over a running status")
precondition(catalog.items[1].statusLabel == "需要你授权")
precondition(catalog.items[0].statusLabel == "正在工作")
precondition(catalog.items[1].updatedAt == 1757000003000, "awaiting time is the newer stamp")
precondition(catalog.items[0].updatedAt == 1757000002000)
precondition(catalog.items[0].title == "Build the widget")
precondition(catalog.items.map(\.agentLogoText) == ["CX", "CC", "GE", "AC"], "cliType stands in for a missing agentType")
precondition(catalog.items[2].agentLogoKind == "gemini")
precondition(catalog.items.allSatisfy { $0.permissionCommand == nil })

let emptyCatalog = LiveActivityCatalog.state(catalogJSON: #"{"sessions": []}"#)
precondition(emptyCatalog.items.isEmpty && !emptyCatalog.isActive && emptyCatalog.totalCount == 0)
precondition(!LiveActivityCatalog.state(catalogJSON: "not json").isActive, "a broken catalog starts nothing")

precondition(
  LodyActivityAttributes.activityId(workspaceId: "ws1", userId: "u1") == "lody-conversations:v5:ws1:u1"
)

print("PASS: catalog mapping skips idle sessions, ranks awaiting first, and maps agent glyphs")
