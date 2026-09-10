import UIKit

/// A short background allowance for a user send, without a system Live Activity.
/// Expiration releases local execution time; it never cancels the remote agent.
@MainActor
final class SessionBackgroundTasks {
  static let shared = SessionBackgroundTasks()
  private struct Work {
    let owner: String
    let task: UIBackgroundTaskIdentifier
  }
  private var work: [String: Work] = [:]
  #if DEBUG
  private(set) var debugState = "idle"
  var debugCount: Int { work.count }
  func debugExpire() {
    for id in work.keys { expire(id) }
  }
  #endif

  func begin(owner: String) -> String? {
    guard UIApplication.shared.applicationState == .active else { return nil }
    let id = UUID().uuidString
    let task = UIApplication.shared.beginBackgroundTask(withName: "Session send") { [weak self] in
      self?.expire(id)
    }
    guard task != .invalid else {
      #if DEBUG
      debugState = "unavailable"
      #endif
      return nil
    }
    work[id] = Work(owner: owner, task: task)
    #if DEBUG
    debugState = "running"
    #endif
    return id
  }

  func update(_ value: [String: Any], owner: String) {
    guard let id = value["id"] as? String, work[id]?.owner == owner,
          let state = value["state"] as? String else { return }
    switch state {
    case "completed", "waiting": finish(id, success: true)
    case "failed": finish(id, success: false)
    default: break
    }
  }

  private func expire(_ id: String) {
    guard work[id] != nil else { return }
    finish(id, success: false)
    #if DEBUG
    debugState = "expired"
    #endif
  }

  func finish(_ id: String, success: Bool) {
    guard let current = work.removeValue(forKey: id) else { return }
    UIApplication.shared.endBackgroundTask(current.task)
    #if DEBUG
    debugState = success ? "completed" : "stopped"
    #endif
  }

  func finishAll(owner: String) {
    for (id, current) in work where current.owner == owner { finish(id, success: false) }
  }
}
