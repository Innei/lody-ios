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
