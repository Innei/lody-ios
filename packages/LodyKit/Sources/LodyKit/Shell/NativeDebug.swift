import LodyCore
import UIKit

@MainActor
enum NativeDebug {
  static func start(in window: UIWindow) {
    precondition(LodyUIVerify.enabled)
    if LodyUIVerify.home {
      do { try NativeHomeFixture.prepare() }
      catch { preconditionFailure("Invalid offline fixture: \(error)") }
    }
    let root: UIViewController = LodyUIVerify.has("--ui-verify-home") ? HomeController() : NativeDebugController()
    LodyShell.shared.start(in: window, content: root)
    let ready = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    ready.isAccessibilityElement = true
    ready.accessibilityIdentifier = "ui-verify-ready"
    ready.accessibilityLabel = "Offline native fixtures ready"
    window.addSubview(ready)
  }

  static func open(_ params: [String: String]) {
    guard LodyUIVerify.enabled || _isDebugAssertConfiguration() else { return }
    guard let scenario = params["verifyCase"] else {
      LodyShell.shared.pushRootNative(NativeDebugController(), title: "Debug")
      return
    }
    if scenario == "home-native-alert" {
      let alert = UIAlertController(title: "Layout verification", message: nil, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      LodyShell.shared.presenter?.present(alert, animated: true)
      return
    }
    if scenario == "home-file-preview" {
      guard let home = HomeController.current,
            let content = LodyNativePages.make("file-diff-preview", params: "{}") else {
        preconditionFailure("Home file preview requires an open offline Home session")
      }
      LodyShell.shared.presentDetail(content, title: String(localized: "diff.title", bundle: .lody), from: home, push: true, detents: [1])
      return
    }
    let content: UIViewController
    var id = scenario
    var fields: [String: Any] = [:]
    let variants = ["session-preview-": "session-preview", "activity-preview-": "activity-preview",
      "settings-baseline-": "settings-baseline", "edit-message-": "edit-message-preview"]
    for (prefix, page) in variants where scenario.hasPrefix(prefix) && scenario != page {
      id = page; fields["scenario"] = String(scenario.dropFirst(prefix.count)); break
    }
    if ["send-queue", "send-guide", "send-interrupt", "send-scroll-guide", "send-scroll-queue", "send-scroll-normal"].contains(scenario) {
      id = "send-preview"
      fields["queue"] = scenario != "send-scroll-normal"
      fields["steer"] = scenario != "send-interrupt"
      fields["longContext"] = scenario.hasPrefix("send-scroll-")
      fields["queuedMessageBehavior"] = scenario.hasSuffix("guide") ? "guide" : "queue"
    }
    let aliases = ["pull-request-preview": "pull-request-native-preview", "permission-native-waiting": "permission-native-preview",
      "appearance-preview": "settings", "diagnostics-settings-preview": "settings",
      "preferences-preview": "preferences", "queued-message-behavior-preview": "preferences",
      "project-preview-empty": "project-preview", "project-preview-offline": "project-preview"]
    id = aliases[id] ?? id
    if scenario == "permission-native-waiting" { fields["waiting"] = true }
    if scenario == "item-detail-preview" { fields["scenario"] = "paging" }
    if scenario == "project-preview-empty" || scenario == "project-preview-offline" { fields["projectId"] = "preview-empty" }
    if scenario == "project-preview-offline" { fields["offline"] = true }
    if ["create-parity", "create-recovery", "create-scope", "model-memory", "project-picker-preview"].contains(scenario) {
      content = CreateSessionPreviewController(scenario: scenario == "project-picker-preview" ? "create-parity" : scenario)
    } else {
      guard let page = LodyNativePages.make(id, params: SessionController.json(fields)) else {
        preconditionFailure("Missing native verification scene: \(scenario)")
      }
      content = page
    }
    let onboarding = content is OnboardingController
    let regular = LodyShell.shared.presenter?.traitCollection.horizontalSizeClass == .regular
    LodyShell.shared.presentNative(content, title: content.title ?? "", detents: [1], grabber: !onboarding,
      dismissible: !onboarding, style: regular ? "formSheet" : "pageSheet",
      headerShown: !onboarding && !(content is CreateSessionHostController))
  }
}

final class NativeDebugController: UITableViewController {
  private let cases = ["create-parity", "session-preview-live", "permission-native-preview", "edit-message-preview",
    "session-share-preview", "workspace-changes-preview", "file-content-preview", "file-diff-preview",
    "notification-preview", "onboarding-preview", "activity-preview", "settings-baseline-live",
    "ai-usage-preview", "memory-preview", "diagnostics-preview"]
  init() { super.init(style: .insetGrouped); title = "Debug" }
  @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
  private var runtimeActions: [String] {
    var actions = ["Runtime status", "Hang runtime", "Restart runtime"]
    #if DEBUG
    actions.append("Verify OneSignal subscription")
    #endif
    return actions
  }
  override func numberOfSections(in tableView: UITableView) -> Int { 2 }
  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    section == 0 ? cases.count : runtimeActions.count
  }
  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    let label = indexPath.section == 0 ? cases[indexPath.row] : runtimeActions[indexPath.row]
    cell.textLabel?.text = label
    cell.accessibilityIdentifier = label
    cell.accessoryType = .disclosureIndicator
    return cell
  }
  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    if indexPath.section == 0 {
      NativeDebug.open(["verifyCase": cases[indexPath.row]])
      return
    }
    guard let runtime = DataRuntime.current else { preconditionFailure("Runtime owner is missing") }
    switch indexPath.row {
    case 0:
      let alert = UIAlertController(title: "Runtime status", message: String(describing: runtime.status()), preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      present(alert, animated: true)
    case 1: runtime.debugHang()
    case 2: runtime.debugRestart()
    #if DEBUG
    case 3:
      PushNotifications.shared.onRegistered = { [weak self] in
        guard let self else { return }
        PushNotifications.shared.verify(from: self)
      }
      PushNotifications.shared.verify(from: self)
    #endif
    default: preconditionFailure("Unknown runtime action")
    }
  }
}

@MainActor
enum NativeHomeFixture {
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
