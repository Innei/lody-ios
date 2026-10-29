import Foundation

public struct SettingsMachinePresence: Decodable, Equatable, Sendable {
  public var state = "unknown"
  public var onlineMachineIds: [String] = []

  public static let unknown = SettingsMachinePresence()

  public func status(of machine: String) -> String {
    guard state == "live" else { return "unknown" }
    return onlineMachineIds.contains(machine) ? "online" : "offline"
  }

  public init(state: String = "unknown", onlineMachineIds: [String] = []) {
    self.state = state
    self.onlineMachineIds = onlineMachineIds
  }
}

public struct SettingsProject: Decodable, Equatable, Sendable {
  public var id: String
  public var machineId: String
  public var name: String
  public var rootPath: String

  public init(id: String, machineId: String, name: String, rootPath: String) {
    self.id = id
    self.machineId = machineId
    self.name = name
    self.rootPath = rootPath
  }
}

public struct SettingsCatalog: Decodable, Equatable, Sendable {
  public var projects: [SettingsProject] = []
  public var machineNames: [String: String] = [:]

  public init(projects: [SettingsProject] = [], machineNames: [String: String] = [:]) {
    self.projects = projects
    self.machineNames = machineNames
  }

  private enum CodingKeys: String, CodingKey { case projects, sessions, machineIds, machineNames }
  private struct Opaque: Decodable {
    public init(from decoder: any Decoder) throws {}
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    _ = try container.decode([Opaque].self, forKey: .sessions)
    _ = try container.decode([Opaque].self, forKey: .machineIds)
    projects = try container.decode([SettingsProject].self, forKey: .projects)
    machineNames = (try? container.decodeIfPresent([String: String].self, forKey: .machineNames)) ?? [:]
  }
}

public struct SettingsWorkspace: Equatable, Sendable {
  public var userId = ""
  public var workspaceId = ""
  public var connected = true
  public var presence = SettingsMachinePresence.unknown
  public var catalog = SettingsCatalog()

  public var key: String { userId.isEmpty || workspaceId.isEmpty ? "" : "\(userId):\(workspaceId)" }

  public static func decode(state: String, raw: String) -> SettingsWorkspace {
    struct Scoped: Decodable {
      public var workspaceId = ""
      public var presence = SettingsMachinePresence.unknown

      public init(workspaceId: String = "", presence: SettingsMachinePresence = SettingsMachinePresence.unknown) {
        self.workspaceId = workspaceId
        self.presence = presence
      }
    }
    struct State: Decodable {
      public var userId = ""
      public var workspaceId = ""
      public var connected = false
      public var presence: Scoped?

      public init(userId: String = "", workspaceId: String = "", connected: Bool = false, presence: Scoped? = nil) {
        self.userId = userId
        self.workspaceId = workspaceId
        self.connected = connected
        self.presence = presence
      }
    }
    struct Saved: Decodable { var catalog: SettingsCatalog }
    guard let parsed = try? JSONDecoder().decode(State.self, from: Data(state.utf8)) else { return SettingsWorkspace() }
    var workspace = SettingsWorkspace(userId: parsed.userId, workspaceId: parsed.workspaceId, connected: parsed.connected)
    if let scoped = parsed.presence, scoped.workspaceId == parsed.workspaceId { workspace.presence = scoped.presence }
    workspace.catalog = (try? JSONDecoder().decode(Saved.self, from: Data(raw.utf8)))?.catalog ?? SettingsCatalog()
    return workspace
  }

  public init(userId: String = "", workspaceId: String = "", connected: Bool = true, presence: SettingsMachinePresence = SettingsMachinePresence.unknown, catalog: SettingsCatalog = SettingsCatalog()) {
    self.userId = userId
    self.workspaceId = workspaceId
    self.connected = connected
    self.presence = presence
    self.catalog = catalog
  }
}
