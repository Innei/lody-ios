import Foundation
import LodyData
import Observation

@MainActor
@Observable
final class MacProjectsModel {
  @ObservationIgnored private let services: MacProjectServices
  private var workspace: SettingsWorkspace
  private var visibility: MacVisibility?
  private var current = ""
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
    if current != workspaceId { visibility = nil }
    current = workspaceId
    loading = true
    let result = await Result { try await services.list(workspaceId) }
    guard current == workspaceId else { return }
    loading = false
    visibility = try? result.get()
    failed = visibility == nil
  }

  func setShared(_ row: MacProjectRow, _ shared: Bool, workspaceId: String) async {
    guard row.owned, row.shared != shared, !saving.contains(row.id), let previous = visibility else { return }
    saving.insert(row.id)
    defer { saving.remove(row.id) }
    visibility = Self.with(previous, row, shared)
    let result = await Result { try await services.share(workspaceId, row, shared) }
    guard current == workspaceId else { return }
    switch result {
    case .success(let next): visibility = next
    case .failure:
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
