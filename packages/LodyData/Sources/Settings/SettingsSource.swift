import Foundation

public struct SettingsConnection: Decodable, Equatable, Sendable {
  public var state = "syncing"
  public var machines = 0
  public var syncedAt: Double?

  public init(state: String = "syncing", machines: Int = 0, syncedAt: Double? = nil) {
    self.state = state
    self.machines = machines
    self.syncedAt = syncedAt
  }
}

public struct SettingsState: Equatable, Sendable {
  public var account: AuthAccount?
  public var workspace: AuthWorkspace?
  public var connection = SettingsConnection()
  public var busy = false
  public var error: String?

  public var scope: [String: Any] {
    guard let account, let workspace else { return [:] }
    return ["userId": account.user.id, "workspaceId": workspace.id]
  }

  public init(account: AuthAccount? = nil, workspace: AuthWorkspace? = nil, connection: SettingsConnection = SettingsConnection(), busy: Bool = false, error: String? = nil) {
    self.account = account
    self.workspace = workspace
    self.connection = connection
    self.busy = busy
    self.error = error
  }
}

@MainActor
public final class SettingsSource {
  public let changes: [Notification.Name]
  private let read: @MainActor () -> SettingsState
  private let refreshAction: @MainActor () -> Void
  private let logoutAction: @MainActor () async -> Void

  public init(
    changes: [Notification.Name], read: @escaping @MainActor () -> SettingsState,
    refresh: @escaping @MainActor () -> Void, logout: @escaping @MainActor () async -> Void
  ) {
    self.changes = changes
    self.read = read
    refreshAction = refresh
    logoutAction = logout
  }

  public var state: SettingsState { read() }

  public func refresh() { refreshAction() }

  public func logout() async { await logoutAction() }

  public static let live = SettingsSource(
    changes: [.lodyAuthDidChange, .lodyCatalogDidChange, .lodySettingsPreviewDidChange],
    read: { SettingsPreview.state ?? SettingsSource.published() },
    refresh: { CatalogSession.shared.refresh() },
    logout: { await AuthSession.shared.logout() }
  )

  private static func published() -> SettingsState {
    struct Auth: Decodable {
      public var account: AuthAccount?
      public var busy: Bool?
      public var error: String?
      public var initialWorkspace: String?

      public init(account: AuthAccount? = nil, busy: Bool? = nil, error: String? = nil, initialWorkspace: String? = nil) {
        self.account = account
        self.busy = busy
        self.error = error
        self.initialWorkspace = initialWorkspace
      }
    }
    struct Catalog: Decodable {
      public var userId: String?
      public var workspaceId: String?
      public var connection: SettingsConnection?

      public init(userId: String? = nil, workspaceId: String? = nil, connection: SettingsConnection? = nil) {
        self.userId = userId
        self.workspaceId = workspaceId
        self.connection = connection
      }
    }
    let auth = try? JSONDecoder().decode(Auth.self, from: Data(AuthSession.published.json.utf8))
    let catalog = try? JSONDecoder().decode(Catalog.self, from: Data(CatalogSession.published.json.utf8))
    var state = SettingsState(
      account: auth?.account, connection: catalog?.connection ?? SettingsConnection(), busy: auth?.busy ?? false,
      error: auth?.error
    )
    if let account = auth?.account {
      let scoped = catalog?.userId == account.user.id
      let selected = scoped ? catalog?.workspaceId : auth?.initialWorkspace
      state.workspace = account.workspaces.first { $0.id == selected } ?? account.workspaces.first
    }
    return state
  }
}

// Native offline fixtures publish their account independently of authenticated services.
@MainActor
public enum SettingsPreview: Sendable {
  public private(set) static var state: SettingsState?

  public static func set(_ json: String) {
    struct Payload: Decodable {
      public var account: AuthAccount?
      public var workspaceId: String?
      public var connection: SettingsConnection?

      public init(account: AuthAccount? = nil, workspaceId: String? = nil, connection: SettingsConnection? = nil) {
        self.account = account
        self.workspaceId = workspaceId
        self.connection = connection
      }
    }
    guard LodyUIVerify.enabled else { return }
    let payload = try? JSONDecoder().decode(Payload.self, from: Data(json.utf8))
    state = payload.map { payload in
      SettingsState(
        account: payload.account,
        workspace: payload.account?.workspaces.first { $0.id == payload.workspaceId } ?? payload.account?.workspaces.first,
        connection: payload.connection ?? SettingsConnection(state: "live")
      )
    }
    NotificationCenter.default.post(name: .lodySettingsPreviewDidChange, object: nil)
  }
}

extension Notification.Name {
  public static let lodySettingsPreviewDidChange = Notification.Name("LodySettingsPreviewDidChange")
}
