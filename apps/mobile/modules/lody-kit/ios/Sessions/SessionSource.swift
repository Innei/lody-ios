import Foundation

struct SessionListState: Equatable, Sendable {
  var userId = ""
  var workspaceId = ""
  var loading = false
  var connected = true
  var presence = SettingsMachinePresence.unknown
  var workspaces: [AuthWorkspace] = []
  var catalog = SessionCatalog()

  var workspace: AuthWorkspace? { workspaces.first { $0.id == workspaceId } }

  var key: String { userId.isEmpty || workspaceId.isEmpty ? "" : "\(userId):\(workspaceId)" }
}

enum SessionWrite: Sendable {
  case archive(Bool)
  case pin(Bool)
  case read(Double)
  case rename(String)
  case delete([String])
}

typealias SessionWriteService = @MainActor (_ workspaceId: String, _ sessionId: String, _ write: SessionWrite) async throws -> Void

@MainActor
final class SessionSource {
  let changes: [Notification.Name]
  let write: SessionWriteService
  private let read: @MainActor () -> SessionListState
  private let rawSession: @MainActor (String) -> String?

  init(
    changes: [Notification.Name], read: @escaping @MainActor () -> SessionListState,
    raw: @escaping @MainActor (String) -> String? = { _ in nil }, write: @escaping SessionWriteService
  ) {
    self.changes = changes
    self.read = read
    rawSession = raw
    self.write = write
  }

  var state: SessionListState { read() }

  func raw(_ sessionId: String) -> String? { rawSession(sessionId) }

  static let live = SessionSource(
    changes: [.lodyAuthDidChange, .lodyCatalogDidChange, .lodySessionCatalogPreviewDidChange, .lodySessionViewsDidChange],
    read: { SessionCatalogPreview.state ?? SessionPublished.state() },
    raw: { id in SessionCatalogPreview.state == nil ? SessionPublished.raw(id) : SessionCatalogPreview.raw(id) },
    write: { workspaceId, sessionId, write in
      if LodyPreviewBridge.active, case .delete(let ids) = write {
        try await LodyPreviewBridge.request("deleteSessions", ["sessionId": sessionId, "sessionIds": ids])
        return
      }
      try await SessionActions.cloud(workspaceId, sessionId, write)
    }
  )

  // Mirrors the JS session view store: a local watermark that clears unread emphasis.
  nonisolated static func views(userId: String, workspaceId: String) async -> [String: Double] {
    guard !userId.isEmpty, !workspaceId.isEmpty,
      let data = try? JSONSerialization.data(withJSONObject: [userId, workspaceId], options: .withoutEscapingSlashes)
    else { return [:] }
    let key = "session-views:\(String(decoding: data, as: UTF8.self))"
    let raw: String? = await withCheckedContinuation { done in
      LocalStore.queue.async { done.resume(returning: try? LocalStore.shared.read(key)) }
    }
    guard let raw, let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { return [:] }
    return object.compactMapValues { ($0 as? NSNumber)?.doubleValue }.filter { $0.value.isFinite }
  }

  // The watermark is the message time, not the device clock, so later messages regain emphasis.
  static func markViewed(userId: String, workspaceId: String, sessionId: String, at lastMessageAt: Double?) {
    guard let lastMessageAt, lastMessageAt.isFinite, !userId.isEmpty, !workspaceId.isEmpty,
      let data = try? JSONSerialization.data(withJSONObject: [userId, workspaceId], options: .withoutEscapingSlashes)
    else { return }
    let key = "session-views:\(String(decoding: data, as: UTF8.self))"
    let generation = LocalStore.shared.generation
    LocalStore.queue.async {
      let raw = (try? LocalStore.shared.read(key)) ?? nil
      var views = raw.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
      guard ((views[sessionId] as? NSNumber)?.doubleValue ?? -.infinity) < lastMessageAt else { return }
      views[sessionId] = lastMessageAt
      let saved: Bool
      if let json = try? JSONSerialization.data(withJSONObject: views) {
        saved = (try? LocalStore.shared.write(key, String(decoding: json, as: UTF8.self), generation: generation)) != nil
      } else {
        saved = false
      }
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          if saved {
            NotificationCenter.default.post(name: .lodySessionViewsDidChange, object: nil)
          } else {
            LodyToastOverlay.shared.show(message: LodyStrings.text("catalog.toast.localSaveFailed"), kind: "error")
          }
        }
      }
    }
  }

  static func rawSession(in catalog: Any?, _ id: String) -> String? {
    guard let sessions = catalog as? [Any],
      let session = sessions.first(where: { ($0 as? [String: Any])?["id"] as? String == id }),
      let data = try? JSONSerialization.data(withJSONObject: session)
    else { return nil }
    return String(decoding: data, as: UTF8.self)
  }
}

@MainActor
enum SessionPublished {
  private static var cache: (key: String, catalog: SessionCatalog)?

  static func state() -> SessionListState {
    struct Auth: Decodable {
      var account: AuthAccount?
      var initialWorkspace: String?
    }
    struct Scoped: Decodable {
      var workspaceId: String?
      var presence: SettingsMachinePresence?
    }
    struct Catalog: Decodable {
      var userId: String?
      var workspaceId: String?
      var loading: Bool?
      var connected: Bool?
      var catalogRevision: Int?
      var presence: Lossy<Scoped>?
      var pendingSessions: [Lossy<SessionItem>]?
    }
    let auth = try? JSONDecoder().decode(Auth.self, from: Data(AuthSession.published.json.utf8))
    guard let account = auth?.account else { return SessionListState() }
    let published = try? JSONDecoder().decode(Catalog.self, from: Data(CatalogSession.published.json.utf8))
    let scoped = published?.userId == account.user.id
    let selected = scoped ? published?.workspaceId : auth?.initialWorkspace
    let workspace = account.workspaces.first { $0.id == selected } ?? account.workspaces.first
    var state = SessionListState(
      userId: account.user.id, workspaceId: workspace?.id ?? "", loading: !scoped, workspaces: account.workspaces
    )
    guard scoped, let published else { return state }
    state.loading = published.loading ?? false
    state.connected = published.connected ?? true
    if let scoped = published.presence?.value, scoped.workspaceId == published.workspaceId {
      state.presence = scoped.presence ?? .unknown
    }
    let key = "\(account.user.id):\(published.workspaceId ?? ""):\(published.catalogRevision ?? -1)"
    let base: SessionCatalog
    if let cache, cache.key == key {
      base = cache.catalog
    } else {
      base = SessionCatalog.decode(saved: Data(CatalogSession.published.raw.utf8)) ?? SessionCatalog()
      cache = (key, base)
    }
    state.catalog = base
    state.catalog.sessions += (published.pendingSessions ?? []).compactMap(\.value)
    return state
  }

  static func raw(_ id: String) -> String? {
    let saved = try? JSONSerialization.jsonObject(with: Data(CatalogSession.published.raw.utf8)) as? [String: Any]
    if let found = SessionSource.rawSession(in: (saved?["catalog"] as? [String: Any])?["sessions"], id) { return found }
    let state = try? JSONSerialization.jsonObject(with: Data(CatalogSession.published.json.utf8)) as? [String: Any]
    return SessionSource.rawSession(in: state?["pendingSessions"], id)
  }
}

// UI verification fixtures that still live in React publish their catalog here.
@MainActor
enum SessionCatalogPreview {
  private(set) static var state: SessionListState?
  private(set) static var catalogJSON = ""
  private static var sessions: [Any] = []

  static func set(_ json: String) {
    guard LodyUIVerify.enabled else { return }
    let payload = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    let account = payload?["account"] as? [String: Any]
    guard let payload, let catalog = payload["catalog"] as? [String: Any],
      let data = try? JSONSerialization.data(withJSONObject: ["catalog": catalog]),
      let decoded = SessionCatalog.decode(saved: data),
      let raw = try? JSONSerialization.data(withJSONObject: catalog)
    else {
      if state != nil { reset() }
      return
    }
    sessions = catalog["sessions"] as? [Any] ?? []
    catalogJSON = String(decoding: raw, as: UTF8.self)
    let workspaceId = payload["workspaceId"] as? String ?? ""
    let workspaces = (try? JSONSerialization.data(withJSONObject: account?["workspaces"] ?? []))
      .flatMap { try? JSONDecoder().decode([AuthWorkspace].self, from: $0) } ?? []
    var next = SessionListState(
      userId: (account?["user"] as? [String: Any])?["id"] as? String ?? "", workspaceId: workspaceId, workspaces: workspaces,
      catalog: decoded
    )
    if let scoped = payload["presence"] as? [String: Any], scoped["workspaceId"] as? String == workspaceId,
      let data = try? JSONSerialization.data(withJSONObject: scoped["presence"] ?? [:]),
      let presence = try? JSONDecoder().decode(SettingsMachinePresence.self, from: data) {
      next.presence = presence
    }
    state = next
    NotificationCenter.default.post(name: .lodySessionCatalogPreviewDidChange, object: nil)
  }

  static func raw(_ id: String) -> String? { SessionSource.rawSession(in: sessions, id) }

  private static func reset() {
    state = nil
    catalogJSON = ""
    sessions = []
    LodyPreviewBridge.reset()
    NotificationCenter.default.post(name: .lodySessionCatalogPreviewDidChange, object: nil)
  }
}

extension Notification.Name {
  static let lodySessionCatalogPreviewDidChange = Notification.Name("LodySessionCatalogPreviewDidChange")
  static let lodySessionViewsDidChange = Notification.Name("LodySessionViewsDidChange")
}
