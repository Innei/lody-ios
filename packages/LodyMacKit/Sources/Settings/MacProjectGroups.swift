import Foundation
import LodyData
import Observation

struct MacVisibility: Codable, Equatable, Sendable {
  struct Row: Codable, Equatable, Sendable {
    var machineId: String
    var localProjectId: String
    var ownerUserId: String
    var sharedWithTeam: Bool
    var updatedAt: Double
  }

  var userId: String
  var rows: [Row]
}

struct MacProjectRow: Identifiable, Equatable {
  let machineId: String
  let localProjectId: String
  let name: String
  let path: String
  let owned: Bool
  let shared: Bool?
  var id: String { "\(machineId):local:\(localProjectId)" }
}

struct MacProjectGroup: Identifiable, Equatable {
  let machineId: String
  let name: String
  let status: String
  var rows: [MacProjectRow]
  var id: String { machineId }
}

enum MacProjectGroups {
  static func make(visibility: MacVisibility?, catalog: SettingsCatalog, presence: SettingsMachinePresence) -> [MacProjectGroup] {
    var groups: [String: MacProjectGroup] = [:]
    func append(_ row: MacProjectRow) {
      let name = catalog.machineNames[row.machineId].flatMap { $0.isEmpty ? nil : $0 }
      groups[row.machineId, default: MacProjectGroup(
        machineId: row.machineId, name: name ?? row.machineId, status: presence.status(of: row.machineId), rows: []
      )].rows.append(row)
    }
    for project in catalog.projects {
      let prefix = "\(project.machineId):local:"
      guard project.id.hasPrefix(prefix) else { continue }
      let local = String(project.id.dropFirst(prefix.count))
      let known = visibility?.rows.first { $0.machineId == project.machineId && $0.localProjectId == local }
      append(MacProjectRow(
        machineId: project.machineId, localProjectId: local, name: project.name.isEmpty ? local : project.name,
        path: project.rootPath, owned: known.map { $0.ownerUserId == visibility?.userId } ?? false, shared: known?.sharedWithTeam
      ))
    }
    return groups.values.sorted { a, b in
      let named = (catalog.machineNames[a.machineId] != nil, catalog.machineNames[b.machineId] != nil)
      if named.0 != named.1 { return named.0 }
      return a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
  }
}

@MainActor
struct MacProjectServices {
  var workspace: @MainActor () -> SettingsWorkspace
  var list: @MainActor (_ workspaceId: String) async throws -> MacVisibility
  var share: @MainActor (_ workspaceId: String, MacProjectRow, Bool) async throws -> MacVisibility

  private struct Request: Encodable {
    var page = "projects"
    var workspaceId: String
    var action: String
    var machineId: String?
    var localProjectId: String?
    var sharedWithTeam: Bool?
  }

  static var live: MacProjectServices {
    MacProjectServices(
      workspace: { SettingsWorkspace.decode(state: CatalogSession.published.json, raw: CatalogSession.published.raw) },
      list: { try await run(Request(workspaceId: $0, action: "list")) },
      share: { workspace, row, shared in
        try await run(Request(workspaceId: workspace, action: "set", machineId: row.machineId, localProjectId: row.localProjectId, sharedWithTeam: shared))
      }
    )
  }

  private static func run(_ request: Request) async throws -> MacVisibility {
    let payload = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
    return try JSONDecoder().decode(MacVisibility.self, from: Data(try await WorkspaceSettingsCloud.run(payload).utf8))
  }
}

@MainActor
@Observable
final class MacProjectsModel {
  @ObservationIgnored private let services: MacProjectServices
  private var workspace: SettingsWorkspace
  private var visibility: MacVisibility?
  private(set) var loading = false
  private(set) var failed = false
  private(set) var saving: Set<String> = []
  var shareFailed = false

  init(services: MacProjectServices) {
    self.services = services
    workspace = services.workspace()
  }

  var groups: [MacProjectGroup] {
    MacProjectGroups.make(visibility: visibility, catalog: workspace.catalog, presence: workspace.connected ? workspace.presence : .unknown)
  }

  func refreshCatalog() {
    workspace = services.workspace()
  }

  func load(workspaceId: String) async {
    refreshCatalog()
    loading = true
    defer { loading = false }
    do {
      visibility = try await services.list(workspaceId)
      failed = false
    } catch {
      visibility = nil
      failed = true
    }
  }

  func setShared(_ row: MacProjectRow, _ shared: Bool, workspaceId: String) async {
    guard row.owned, row.shared != shared, !saving.contains(row.id), let previous = visibility else { return }
    saving.insert(row.id)
    defer { saving.remove(row.id) }
    visibility = Self.with(previous, row, shared)
    do {
      visibility = try await services.share(workspaceId, row, shared)
    } catch {
      visibility = Self.with(visibility ?? previous, row, !shared)
      shareFailed = true
    }
  }

  private static func with(_ visibility: MacVisibility, _ row: MacProjectRow, _ shared: Bool) -> MacVisibility {
    var next = visibility
    for index in next.rows.indices where next.rows[index].machineId == row.machineId && next.rows[index].localProjectId == row.localProjectId {
      next.rows[index].sharedWithTeam = shared
    }
    return next
  }
}
