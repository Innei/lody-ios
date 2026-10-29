import Foundation
import LodyData

struct MacSidebarModel: Equatable {
  struct Row: Equatable {
    let id: String
    let title: String
    let status: String
    let attention: Bool
    let unread: Bool
  }

  struct Group: Equatable {
    let id: String
    let title: String
    var rows: [Row]
  }

  var needsApproval = 0
  var pinned: [Row] = []
  var groups: [Group] = []

  init() {}

  init(state: SessionListState, query: String = "") {
    let catalog = state.catalog
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let visible = catalog.sessions
      .filter { !$0.archived && $0.parentSessionId == nil }
      .filter { trimmed.isEmpty || $0.title.localizedCaseInsensitiveContains(trimmed) }
      .sorted { ($0.lastMessageAt ?? 0) > ($1.lastMessageAt ?? 0) }
    needsApproval = catalog.sessions.filter { !$0.archived && $0.awaitingUserSince != nil }.count
    pinned = visible.filter(\.pinned).map(Self.row)
    var order: [String] = []
    var rows: [String: [Row]] = [:]
    for session in visible where !session.pinned {
      if rows[session.projectId] == nil { order.append(session.projectId) }
      rows[session.projectId, default: []].append(Self.row(session))
    }
    let names = Dictionary(catalog.projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    groups = order.map { id in
      let name = names[id].flatMap { $0.isEmpty ? nil : $0 }
      return Group(id: id, title: name ?? String(localized: "mac.sidebar.noProject", bundle: .lodyMac), rows: rows[id] ?? [])
    }
  }

  private static func row(_ session: SessionItem) -> Row {
    let title = session.title.isEmpty ? String(localized: "mac.sidebar.untitled", bundle: .lodyMac) : session.title
    let unread = (session.lastMessageAt ?? 0) > max(session.lastReadAt ?? 0, session.lastViewedMessageAt ?? 0)
    return Row(id: session.id, title: title, status: session.status, attention: session.awaitingUserSince != nil, unread: unread)
  }
}
