import Foundation
import LodyCore

struct AuthCatalogScope {
  let account: AuthAccount?
  let localReady: Bool
  let initialWorkspace: String
  let initialCatalog: String?
}

struct CatalogConnection: Encodable, Equatable, Sendable {
  var state = "syncing"
  var machines = 0
  var syncedAt: Int?
}

struct CatalogPresence: Encodable, Equatable, Sendable {
  static let unknown = RuntimeContract.MachinePresence(state: .unknown, onlineMachineIds: [])

  var workspaceId = ""
  var presence = CatalogPresence.unknown
}

struct CatalogSnapshot: Encodable, Sendable {
  var userId = ""
  var workspaceId = ""
  var key = ""
  var loading = false
  var connected = false
  var syncedAt: Int?
  var catalogRevision = 0
  var connection = CatalogConnection()
  var presence = CatalogPresence()

  var json: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
  }
}

struct CatalogDigest: Decodable, Sendable {
  struct Project: Decodable, Sendable {
    let id: String?
    let repoFullName: String?
  }

  struct Opaque: Decodable, Sendable {
    init(from decoder: any Decoder) throws {}
  }

  let projects: [Project]
  let sessions: [Opaque]
  let machineIds: [Opaque]

  var repos: [String: String] {
    Dictionary(projects.compactMap { project in
      guard let id = project.id, let repo = project.repoFullName, !repo.isEmpty else { return nil }
      return (id, repo)
    }, uniquingKeysWith: { _, last in last })
  }

  static func decode(_ json: String) -> CatalogDigest? {
    try? JSONDecoder().decode(CatalogDigest.self, from: Data(json.utf8))
  }
}

struct SavedCatalogDigest: Decodable, Sendable {
  let catalog: CatalogDigest
  let syncedAt: Int?

  private enum CodingKeys: String, CodingKey { case catalog, syncedAt }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    catalog = try container.decode(CatalogDigest.self, forKey: .catalog)
    syncedAt = ((try? container.decodeIfPresent(Double.self, forKey: .syncedAt)) ?? nil).flatMap { Int(exactly: $0.rounded(.towardZero)) }
  }

  static func decode(_ json: String?) -> SavedCatalogDigest? {
    guard let json else { return nil }
    return try? JSONDecoder().decode(SavedCatalogDigest.self, from: Data(json.utf8))
  }
}

final class CatalogPublished: @unchecked Sendable {
  private let lock = NSLock()
  private var state = CatalogSnapshot().json
  private var catalog = "null"

  var json: String { lock.withLock { state } }
  var raw: String { lock.withLock { catalog } }

  func set(_ json: String, catalog: String) -> Bool {
    lock.withLock {
      let changed = state != json
      state = json
      self.catalog = catalog
      return changed
    }
  }
}
