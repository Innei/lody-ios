import Foundation
import LodyCore

public struct AuthCatalogScope: Sendable {
  public let account: AuthAccount?
  public let localReady: Bool
  public let initialWorkspace: String
  public let initialCatalog: String?

  public init(account: AuthAccount?, localReady: Bool, initialWorkspace: String, initialCatalog: String?) {
    self.account = account
    self.localReady = localReady
    self.initialWorkspace = initialWorkspace
    self.initialCatalog = initialCatalog
  }
}

public struct CatalogConnection: Encodable, Equatable, Sendable {
  public var state = "syncing"
  public var machines = 0
  public var syncedAt: Int?

  public init(state: String = "syncing", machines: Int = 0, syncedAt: Int? = nil) {
    self.state = state
    self.machines = machines
    self.syncedAt = syncedAt
  }
}

public struct CatalogPresence: Encodable, Equatable, Sendable {
  public static let unknown = RuntimeContract.MachinePresence(state: .unknown, onlineMachineIds: [])

  public var workspaceId = ""
  public var presence = CatalogPresence.unknown

  public init(workspaceId: String = "", presence: RuntimeContract.MachinePresence = CatalogPresence.unknown) {
    self.workspaceId = workspaceId
    self.presence = presence
  }
}

public struct CatalogSnapshot: Encodable, Sendable {
  public var userId = ""
  public var workspaceId = ""
  public var key = ""
  public var loading = false
  public var connected = false
  public var syncedAt: Int?
  public var catalogRevision = 0
  public var connection = CatalogConnection()
  public var presence = CatalogPresence()
  public var pendingSessions: [RuntimeContract.JSONValue] = []

  public var json: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
  }

  public init(userId: String = "", workspaceId: String = "", key: String = "", loading: Bool = false, connected: Bool = false, syncedAt: Int? = nil, catalogRevision: Int = 0, connection: CatalogConnection = CatalogConnection(), presence: CatalogPresence = CatalogPresence(), pendingSessions: [RuntimeContract.JSONValue] = []) {
    self.userId = userId
    self.workspaceId = workspaceId
    self.key = key
    self.loading = loading
    self.connected = connected
    self.syncedAt = syncedAt
    self.catalogRevision = catalogRevision
    self.connection = connection
    self.presence = presence
    self.pendingSessions = pendingSessions
  }
}

public struct CatalogDigest: Decodable, Sendable {
  public struct Project: Decodable, Sendable {
    public let id: String?
    public let repoFullName: String?

    public init(id: String?, repoFullName: String?) {
      self.id = id
      self.repoFullName = repoFullName
    }
  }

  public struct Session: Decodable, Sendable {
    public let id: String?
    public let latestUserMsgId: String?

    private enum CodingKeys: String, CodingKey { case id, latestUserMsgId }

    public init(from decoder: any Decoder) throws {
      let container = try? decoder.container(keyedBy: CodingKeys.self)
      id = (try? container?.decodeIfPresent(String.self, forKey: .id)) ?? nil
      latestUserMsgId = (try? container?.decodeIfPresent(String.self, forKey: .latestUserMsgId)) ?? nil
    }
  }

  public struct Opaque: Decodable, Sendable {
    public init(from decoder: any Decoder) throws {}
  }

  public let projects: [Project]
  public let sessions: [Session]
  public let machineIds: [Opaque]

  public var latestUserMessages: [String: String] {
    Dictionary(sessions.compactMap { session in session.id.map { ($0, session.latestUserMsgId ?? "") } },
               uniquingKeysWith: { first, _ in first })
  }

  public var repos: [String: String] {
    Dictionary(projects.compactMap { project in
      guard let id = project.id, let repo = project.repoFullName, !repo.isEmpty else { return nil }
      return (id, repo)
    }, uniquingKeysWith: { _, last in last })
  }

  public static func decode(_ json: String) -> CatalogDigest? {
    try? JSONDecoder().decode(CatalogDigest.self, from: Data(json.utf8))
  }

  public init(projects: [Project], sessions: [Session], machineIds: [Opaque]) {
    self.projects = projects
    self.sessions = sessions
    self.machineIds = machineIds
  }
}

public struct SavedCatalogDigest: Decodable, Sendable {
  public let catalog: CatalogDigest
  public let syncedAt: Int?

  private enum CodingKeys: String, CodingKey { case catalog, syncedAt }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    catalog = try container.decode(CatalogDigest.self, forKey: .catalog)
    syncedAt = ((try? container.decodeIfPresent(Double.self, forKey: .syncedAt)) ?? nil).flatMap { Int(exactly: $0.rounded(.towardZero)) }
  }

  public static func decode(_ json: String?) -> SavedCatalogDigest? {
    guard let json else { return nil }
    return try? JSONDecoder().decode(SavedCatalogDigest.self, from: Data(json.utf8))
  }
}

public final class CatalogPublished: @unchecked Sendable {
  private let lock = NSLock()
  private var state = CatalogSnapshot().json
  private var catalog = "null"

  public init() {}

  public var json: String { lock.withLock { state } }
  public var raw: String { lock.withLock { catalog } }

  public func set(_ json: String, catalog: String) -> Bool {
    lock.withLock {
      let changed = state != json
      state = json
      self.catalog = catalog
      return changed
    }
  }
}
