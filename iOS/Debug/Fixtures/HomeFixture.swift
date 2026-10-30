import LodyCore
import UIKit

@MainActor
enum HomeFixture {
  static var active: Bool { LodyUIVerify.enabled && SessionCatalogPreview.state != nil }
  static func request(_ action: String, _ fields: [String: Any]) async throws {
    precondition(active, "Preview actions require an offline fixture")
    try apply(action, fields)
  }
  static func routingContext() -> NotificationNavigation.Context {
    let state = SessionSource.live.state
    return .init(ready: true, userId: state.userId,
      workspaces: workspaces.map { ($0["id"] as! String, $0["slug"] as? String) },
      selectedId: state.workspaceId, loading: state.loading, connected: state.connected,
      sessionIds: Set(state.catalog.sessions.map(\.id)))
  }
  private static var presence: [String: Any] = ["state": "live", "onlineMachineIds": ["ui", "mini"]]
  private static var polling: Task<Void, Never>?

  private static var catalog: [String: Any] = [:]
  private static var statesCatalog: [String: Any] = [:]
  private static var workspaces: [[String: Any]] = []
  private static var selected = "ui-home"
  private static var rejectedDelete = false

  static func prepare() throws {
    let url = Bundle.main.url(forResource: "DebugHome", withExtension: "json")!
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    catalog = fixture["catalog"] as! [String: Any]
    statesCatalog = relative(fixture["statesCatalog"] as! [String: Any], now: Date().timeIntervalSince1970 * 1000)
    workspaces = fixture["workspaces"] as! [[String: Any]]
    for case let (photo, source as String) in fixture["photoCache"] as? [String: Any] ?? [:] {
      if let url = URL(string: photo), let data = URL(string: source) { LodyListPhoto.prime(url, from: data) }
    }
    selected = "ui-home"; rejectedDelete = false
    for key in ["inboxView", "inboxProjectSort", "inboxExpansion", "inboxPinOrder.ui-home.ui-home"] {
      UserDefaults.standard.removeObject(forKey: key)
    }
    let catalogJSON = SessionController.json(["catalog": catalog, "syncedAt": 0])
    try LocalStore.queue.sync {
      let store = LocalStore.shared
      try store.write("ui-device-presence", "{\"state\":\"live\",\"onlineMachineIds\":[\"ui\",\"mini\"]}")
      try store.write("catalog:ui-home:ui-home", catalogJSON)
      try store.write("pending-sends:ui-home:ui-home", "[]")
      try store.write("draft:ui-home:ui-home:ui-design", "")
      let search = LodyUIVerify.has("--ui-verify-search")
      try store.write("session:[\"ui-home\",\"ui-home\",\"ui-design\"]", fixture[search ? "searchPreviewCache" : "previewCache"] as! String)
      try store.write("session:[\"ui-home\",\"ui-home\",\"ui-search\"]", search ? fixture["olderSearchCache"] as! String : "null")
      try store.write("session:[\"ui-home\",\"ui-states\",\"st-sync\"]", fixture["statesProseCache"] as! String)
    }
    publish()
    polling?.cancel()
    polling = Task {
      var previous = ""
      while !Task.isCancelled {
        let raw: String? = await withCheckedContinuation { done in
          LocalStore.queue.async { done.resume(returning: try? LocalStore.shared.read("ui-device-presence")) }
        }
        if let raw, raw != previous {
          previous = raw
          presence = try! JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
          publish()
        }
        try? await Task.sleep(for: .milliseconds(500))
      }
    }
  }

  static func apply(_ action: String, _ fields: [String: Any]) throws {
    switch action {
    case "selectWorkspace": selected = fields["workspaceId"] as! String
    case "updateWorkspace", "updateWorkspaceIcon":
      let id = fields["workspaceId"] as! String
      guard let index = workspaces.firstIndex(where: { $0["id"] as? String == id }) else { preconditionFailure("Unknown fixture workspace") }
      if action == "updateWorkspace" { workspaces[index]["name"] = fields["name"] }
      else { workspaces[index]["image"] = fields["uri"] }
    case "deleteSessions":
      if fields["sessionId"] as? String == "ui-search", !rejectedDelete {
        rejectedDelete = true
        throw NSError(domain: "OfflineFixture", code: 1)
      }
      let ids = fields["sessionIds"] as! [String]
      catalog["sessions"] = (catalog["sessions"] as! [[String: Any]]).filter { !ids.contains($0["id"] as! String) }
    default: preconditionFailure("Unknown fixture action: \(action)")
    }
    publish()
  }

  private static func relative(_ fixture: [String: Any], now: Double) -> [String: Any] {
    var result = fixture
    result["sessions"] = (fixture["sessions"] as! [[String: Any]]).map { session in
      var session = session
      for (offset, field) in [("ago", "lastMessageAt"), ("readAgo", "lastReadAt"), ("awaitingAgo", "awaitingUserSince")] {
        guard let seconds = session.removeValue(forKey: offset) as? Double else { continue }
        session[field] = now - seconds * 1000
      }
      return session
    }
    return result
  }

  private static func publish() {
    let catalogs = ["ui-home": catalog, "ui-states": statesCatalog]
    let empty: [String: Any] = ["projects": [], "sessions": [], "machineIds": []]
    let payload: [String: Any] = ["account": ["user": ["id": "ui-home", "name": "UI Preview", "email": ""], "workspaces": workspaces],
      "workspaceId": selected, "catalog": catalogs[selected] ?? empty,
      "presence": ["workspaceId": selected, "presence": presence]]
    let json = String(decoding: try! JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
    SettingsPreview.set(json)
    SessionCatalogPreview.set(json)
  }
}
