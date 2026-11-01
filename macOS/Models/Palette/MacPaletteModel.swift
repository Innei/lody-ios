import Foundation
import LodyData

struct MacPaletteModel {
  enum Mode { case search, projects }
  enum Scope: Int, CaseIterable { case all, chats, projects }
  enum Destination: Equatable { case chat(String), project(String?), newChat, manageProjects }
  struct Item: Equatable {
    let id: String
    let title: String
    let context: String
    let symbol: String
    let section: String
    let destination: Destination
  }
  let state: SessionListState
  let mode: Mode

  func items(query: String, scope: Scope = .all, machineId: String = "") -> [Item] {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let catalog = state.catalog
    let names = Dictionary(catalog.projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    func matches(_ values: String...) -> Bool { term.isEmpty || values.contains { $0.localizedCaseInsensitiveContains(term) } }
    var result: [Item] = []
    if mode == .search, scope == .all {
      let section = String(localized: "mac.palette.quickActions", bundle: .lodyMac)
      let actions = [
        Item(id: "action:new", title: String(localized: "mac.sidebar.newChat", bundle: .lodyMac), context: "⌘N", symbol: "square.and.pencil", section: section, destination: .newChat),
        Item(id: "action:projects", title: String(localized: "mac.sidebar.manageProjects", bundle: .lodyMac), context: "", symbol: "folder.badge.gearshape", section: section, destination: .manageProjects),
      ]
      result += actions.filter { matches($0.title) }
    }
    if mode == .projects || scope == .projects || (scope == .all && !term.isEmpty) {
      let section = String(localized: "mac.settings.page.projects", bundle: .lodyMac)
      for project in catalog.projects where matches(project.name, project.rootPath) {
        var machines = Set(catalog.sessions.filter { $0.projectId == project.id }.map(\.machineId).filter { !$0.isEmpty })
        if !project.machineId.isEmpty { machines = [project.machineId] }
        if !machineId.isEmpty && !machines.contains(machineId) { continue }
        let labels = machines.sorted().compactMap { catalog.machineNames[$0] }
        let context = ([project.rootPath] + labels).filter { !$0.isEmpty }.joined(separator: " · ")
        result.append(Item(id: "project:" + project.id, title: project.name, context: context, symbol: "folder", section: section, destination: .project(project.id)))
      }
      let chat = String(localized: "mac.composer.chat", bundle: .lodyMac)
      if mode == .projects, machineId.isEmpty, matches(chat) {
        result.append(Item(id: "project:none", title: chat, context: "", symbol: "bubble.left", section: section, destination: .project(nil)))
      }
    }
    if mode == .search && scope != .projects {
      var sessions = catalog.sessions.filter { !$0.archived && $0.parentSessionId == nil }
        .filter { matches($0.title, names[$0.projectId] ?? "", $0.branchName ?? "") }
        .sorted { lhs, rhs in
          let left = lhs.lastMessageAt ?? 0, right = rhs.lastMessageAt ?? 0
          if left == right { return lhs.id < rhs.id }
          return left > right
        }
      if term.isEmpty { sessions = Array(sessions.prefix(5)) }
      let section = term.isEmpty ? String(localized: "mac.palette.recent", bundle: .lodyMac) : String(localized: "mac.palette.chats", bundle: .lodyMac)
      result += sessions.map { session in
        let title = session.title.isEmpty ? String(localized: "mac.sidebar.untitled", bundle: .lodyMac) : session.title
        let context = [names[session.projectId] ?? "", catalog.machineNames[session.machineId] ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        return Item(id: "chat:" + session.id, title: title, context: context, symbol: "bubble.left", section: section, destination: .chat(session.id))
      }
    }
    return result
  }
}
