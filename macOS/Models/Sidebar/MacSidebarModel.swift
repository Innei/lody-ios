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
    let machineId: String
    let machineTitle: String
    var rows: [Row]
  }

  var approvals: [String] = []
  var needsApproval: Int { approvals.count }
  var pinned: [Row] = []
  var groups: [Group] = []

  init() {}

  init(state: SessionListState, query: String = "", projectId: String? = nil, archived: Bool = false) {
    let catalog = state.catalog
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let names = Dictionary(catalog.projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    let visible = catalog.sessions
      .filter { $0.parentSessionId == nil && $0.archived == archived }
      .filter { projectId == nil || $0.projectId == projectId }
      .filter { session in
        trimmed.isEmpty || [session.title, names[session.projectId] ?? "", session.branchName ?? ""]
          .contains { $0.localizedCaseInsensitiveContains(trimmed) }
      }
      .sorted { lhs, rhs in
        if lhs.pinned != rhs.pinned { return lhs.pinned }
        let left = lhs.activityAt.isFinite ? lhs.activityAt : 0
        let right = rhs.activityAt.isFinite ? rhs.activityAt : 0
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
    // Project identity includes the machine: the same repository may run on two hosts.
    for session in visible {
      let machineId = session.machineId
      let id = "project:" + machineId + ":" + session.projectId
      if let index = groups.firstIndex(where: { $0.id == id }) {
        groups[index].rows += rows([session])
      } else {
        let row = Self.row(session, names: names, machines: catalog.machineNames)
        let machine = catalog.machineNames[machineId] ?? String(localized: "mac.sidebar.otherSessions", bundle: .lodyMac)
        groups.append(Group(id: id, title: row.project, machineId: machineId, machineTitle: machine, rows: [row]))
      }
    }
    groups.sort {
      if $0.machineId != $1.machineId {
        let left = catalog.machineIds.firstIndex(of: $0.machineId) ?? Int.max
        let right = catalog.machineIds.firstIndex(of: $1.machineId) ?? Int.max
        if left != right { return left < right }
        return $0.machineId < $1.machineId
      }
      let left = $0.rows.compactMap(\.activityAt).max() ?? 0
      let right = $1.rows.compactMap(\.activityAt).max() ?? 0
      if left != right { return left > right }
      return $0.title.localizedStandardCompare($1.title) == .orderedAscending
    }
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
