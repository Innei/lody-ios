import Foundation
import LodyCore

public struct SessionListState: Equatable, Sendable {
  public var userId = ""
  public var workspaceId = ""
  public var loading = false
  public var connected = true
  public var presence = SettingsMachinePresence.unknown
  public var workspaces: [AuthWorkspace] = []
  public var catalog = SessionCatalog()

  public var workspace: AuthWorkspace? { workspaces.first { $0.id == workspaceId } }

  public var key: String { userId.isEmpty || workspaceId.isEmpty ? "" : "\(userId):\(workspaceId)" }

  public init(userId: String = "", workspaceId: String = "", loading: Bool = false, connected: Bool = true, presence: SettingsMachinePresence = SettingsMachinePresence.unknown, workspaces: [AuthWorkspace] = [], catalog: SessionCatalog = SessionCatalog()) {
    self.userId = userId
    self.workspaceId = workspaceId
    self.loading = loading
    self.connected = connected
    self.presence = presence
    self.workspaces = workspaces
    self.catalog = catalog
  }
}

public enum SessionWrite: Sendable {
  case archive(Bool)
  case pin(Bool)
  case read(Double)
  case rename(String)
  case delete([String])
}

public typealias SessionWriteService = @MainActor (_ workspaceId: String, _ sessionId: String, _ write: SessionWrite) async throws -> Void

@MainActor
public final class SessionSource {
  public let changes: [Notification.Name]
  public let write: SessionWriteService
  private let read: @MainActor () -> SessionListState
  private let rawSession: @MainActor (String) -> String?

  public init(
    changes: [Notification.Name], read: @escaping @MainActor () -> SessionListState,
    raw: @escaping @MainActor (String) -> String? = { _ in nil }, write: @escaping SessionWriteService
  ) {
    self.changes = changes
    self.read = read
    rawSession = raw
    self.write = write
  }

  public var state: SessionListState { read() }

  public func raw(_ sessionId: String) -> String? { rawSession(sessionId) }

  // A persisted local watermark clears unread emphasis.
  public nonisolated static func views(userId: String, workspaceId: String) async -> [String: Double] {
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
  public static func markViewed(userId: String, workspaceId: String, sessionId: String, at lastMessageAt: Double?) {
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
            LodyHosting.current?.toast(String(localized: "catalog.toast.localSaveFailed", bundle: .lodyData), kind: "error")
          }
        }
      }
    }
  }

  public static func rawSession(in catalog: Any?, _ id: String) -> String? {
    guard let sessions = catalog as? [Any],
      let session = sessions.first(where: { ($0 as? [String: Any])?["id"] as? String == id }),
      let data = try? JSONSerialization.data(withJSONObject: session)
    else { return nil }
    return String(decoding: data, as: UTF8.self)
  }
}

@MainActor
public enum SessionPublished: Sendable {
  private static var cache: (key: String, catalog: SessionCatalog)?

  public static func state() -> SessionListState {
    struct Auth: Decodable {
      public var account: AuthAccount?
      public var initialWorkspace: String?

      public init(account: AuthAccount? = nil, initialWorkspace: String? = nil) {
        self.account = account
        self.initialWorkspace = initialWorkspace
      }
    }
    struct Scoped: Decodable {
      public var workspaceId: String?
      public var presence: SettingsMachinePresence?

      public init(workspaceId: String? = nil, presence: SettingsMachinePresence? = nil) {
        self.workspaceId = workspaceId
        self.presence = presence
      }
    }
    struct Catalog: Decodable {
      public var userId: String?
      public var workspaceId: String?
      public var loading: Bool?
      public var connected: Bool?
      public var catalogRevision: Int?
      public var presence: Lossy<Scoped>?
      public var pendingSessions: [Lossy<SessionItem>]?

      public init(userId: String? = nil, workspaceId: String? = nil, loading: Bool? = nil, connected: Bool? = nil, catalogRevision: Int? = nil, presence: Lossy<Scoped>? = nil, pendingSessions: [Lossy<SessionItem>]? = nil) {
        self.userId = userId
        self.workspaceId = workspaceId
        self.loading = loading
        self.connected = connected
        self.catalogRevision = catalogRevision
        self.presence = presence
        self.pendingSessions = pendingSessions
      }
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

  public static func raw(_ id: String) -> String? {
    let saved = try? JSONSerialization.jsonObject(with: Data(CatalogSession.published.raw.utf8)) as? [String: Any]
    if let found = SessionSource.rawSession(in: (saved?["catalog"] as? [String: Any])?["sessions"], id) { return found }
    let state = try? JSONSerialization.jsonObject(with: Data(CatalogSession.published.json.utf8)) as? [String: Any]
    return SessionSource.rawSession(in: state?["pendingSessions"], id)
  }
}

// Native offline fixtures publish their catalog independently of authenticated services.
@MainActor
public enum SessionCatalogPreview: Sendable {
  private static var base: SessionListState?
  private static var observer: NSObjectProtocol?
  public static var state: SessionListState? {
    guard var state = base else { return nil }
    let pending = pendingSessions()
    state.catalog.sessions += try! JSONDecoder().decode([SessionItem].self, from: JSONEncoder().encode(pending))
    return state
  }
  private static func pendingSessions() -> [OutboxValue] {
    guard let base else { return [] }
    let existing = Dictionary(uniqueKeysWithValues: base.catalog.sessions.map { ($0.id, "") })
    return OutboxSession.shared.pendingSessions(user: base.userId, workspace: base.workspaceId, excluding: existing)
  }
  public private(set) static var catalogJSON = ""
  private static var sessions: [Any] = []

  public static func set(_ json: String) {
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
    base = next
    if observer == nil {
      observer = NotificationCenter.default.addObserver(forName: .lodyOutboxDidChange, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { NotificationCenter.default.post(name: .lodySessionCatalogPreviewDidChange, object: nil) }
      }
    }
    NotificationCenter.default.post(name: .lodySessionCatalogPreviewDidChange, object: nil)
  }

  public static func raw(_ id: String) -> String? {
    if let raw = SessionSource.rawSession(in: sessions, id) { return raw }
    guard let pending = pendingSessions().first(where: { $0.object?["id"]?.string == id }) else { return nil }
    return String(decoding: try! JSONEncoder().encode(pending), as: UTF8.self)
  }

  private static func reset() {
    base = nil
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    catalogJSON = ""
    sessions = []
    NotificationCenter.default.post(name: .lodySessionCatalogPreviewDidChange, object: nil)
  }
}

extension Notification.Name {
  public static let lodySessionCatalogPreviewDidChange = Notification.Name("LodySessionCatalogPreviewDidChange")
  public static let lodySessionViewsDidChange = Notification.Name("LodySessionViewsDidChange")
}

extension SessionSource {
  public static func cloud(_ workspaceId: String, _ sessionId: String, _ write: SessionWrite) async throws {
    guard let runtime = DataRuntime.current, runtime.workspace == workspaceId else {
      throw DataRuntime.failure("not_ready", String(localized: "native.runtime.sessionNotSynced", bundle: .lodyData))
    }
    switch write {
    case .archive(let archived):
      _ = try await runtime.workspaceCall(RuntimeContract.Calls.ArchiveSession.self) { workspace, _ in
        .init(workspaceId: workspace, sessionId: sessionId, archived: archived)
      }
    case .pin(let pinned):
      _ = try await runtime.workspaceCall(RuntimeContract.Calls.PinSession.self) { workspace, _ in
        .init(workspaceId: workspace, sessionId: sessionId, pinned: pinned)
      }
    case .read(let at):
      _ = try await runtime.workspaceCall(RuntimeContract.Calls.MarkSessionRead.self) { workspace, _ in
        .init(workspaceId: workspace, sessionId: sessionId, lastReadAt: at)
      }
    case .rename(let title):
      _ = try await runtime.workspaceCall(RuntimeContract.Calls.RenameSession.self) { workspace, _ in
        .init(workspaceId: workspace, sessionId: sessionId, title: title)
      }
    case .delete(let ids):
      let payload = RuntimeJSON.string(["workspaceId": workspaceId, "sessionId": sessionId, "sessionIds": ids])
      guard OutboxSession.shared.allowsDeletion(payload) else {
        throw DataRuntime.failure("session_has_pending_send", "session_has_pending_send")
      }
      _ = try await runtime.workspaceCall(RuntimeContract.Calls.DeleteSession.self) { workspace, _ in
        .init(workspaceId: workspace, sessionId: sessionId, sessionIds: ids)
      }
    }
  }
}
