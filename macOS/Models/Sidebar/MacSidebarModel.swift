import Foundation
import LodyData

struct MacSidebarModel: Equatable {
  struct Row: Equatable {
    let id: String
    let title: String
    let status: String
    let attention: Bool
    let unread: Bool
    let projectId: String
    let project: String
    let branch: String?
    let machine: String?
    let agent: String
    let activityAt: Double?
    let pinned: Bool
    let archived: Bool
  }

  struct Group: Equatable {
    let id: String
    let title: String
    var rows: [Row]
  }

  var approvals: [String] = []
  var needsApproval: Int { approvals.count }
  var pinned: [Row] = []
  var groups: [Group] = []

  init() {}

  init(state: SessionListState, query: String = "", projectId: String? = nil) {
    let catalog = state.catalog
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let names = Dictionary(catalog.projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    let visible = catalog.sessions
      .filter { $0.parentSessionId == nil }
      .filter { projectId == nil || $0.projectId == projectId }
      .filter { session in
        trimmed.isEmpty || [session.title, names[session.projectId] ?? "", session.branchName ?? ""]
          .contains { $0.localizedCaseInsensitiveContains(trimmed) }
      }
      .sorted { lhs, rhs in
        let left = lhs.lastMessageAt ?? 0
        let right = rhs.lastMessageAt ?? 0
        if left == right { return lhs.id < rhs.id }
        return left > right
      }
    approvals = catalog.sessions
      .compactMap { session in session.archived ? nil : session.awaitingUserSince.map { (session.id, $0) } }
      .sorted { $0.1 < $1.1 }
      .map(\.0)
    func rows(_ sessions: [SessionItem]) -> [Row] {
      sessions.map { Self.row($0, names: names, machines: catalog.machineNames) }
    }
    pinned = rows(visible.filter { $0.pinned && !$0.archived })
    let unpinned = visible.filter { !$0.pinned && !$0.archived }
    let working = unpinned.filter { OutboxDispatcher.busy.contains($0.status) && $0.awaitingUserSince == nil }
    let workingIds = Set(working.map(\.id))
    groups = [
      Group(id: "active", title: "", rows: rows(unpinned.filter { !workingIds.contains($0.id) })),
      Group(id: "working", title: String(localized: "mac.sidebar.working", bundle: .lodyMac), rows: rows(working)),
      Group(id: "settled", title: String(localized: "mac.sidebar.settled", bundle: .lodyMac), rows: rows(visible.filter(\.archived))),
    ]
  }

  private static func row(_ session: SessionItem, names: [String: String], machines: [String: String]) -> Row {
    let title = session.title.isEmpty ? String(localized: "mac.sidebar.untitled", bundle: .lodyMac) : session.title
    let unread = (session.lastMessageAt ?? 0) > max(session.lastReadAt ?? 0, session.lastViewedMessageAt ?? 0)
    let project = names[session.projectId].flatMap { $0.isEmpty ? nil : $0 }
      ?? String(localized: "mac.sidebar.noProject", bundle: .lodyMac)
    return Row(id: session.id, title: title, status: session.status, attention: session.awaitingUserSince != nil, unread: unread,
               projectId: session.projectId, project: project, branch: session.branchName, machine: machines[session.machineId],
               agent: session.agentType, activityAt: session.lastMessageAt, pinned: session.pinned, archived: session.archived)
  }
}
