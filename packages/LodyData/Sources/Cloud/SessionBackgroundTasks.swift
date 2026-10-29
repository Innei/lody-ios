import Foundation

/// A short background allowance for a user send, without a system Live Activity.
/// Expiration releases local execution time; it never cancels the remote agent.
@MainActor
public final class SessionBackgroundTasks {
  public static let shared = SessionBackgroundTasks()
  private struct Work {
    public let owner: String
    public let token: AnyObject
  }
  private var work: [String: Work] = [:]
  public private(set) var debugState = "idle"
  public var debugCount: Int { work.count }
  public func debugExpire() {
    for id in work.keys { expire(id) }
  }

  public func begin(owner: String) -> String? {
    guard let host = LodyHosting.current, host.isActive else { return nil }
    let id = UUID().uuidString
    guard let token = host.beginSendAllowance(expired: { [weak self] in self?.expire(id) }) else {
      debugState = "unavailable"
      return nil
    }
    work[id] = Work(owner: owner, token: token)
    debugState = "running"
    return id
  }

  public func update(id: String, state: String, owner: String) {
    guard work[id]?.owner == owner else { return }
    switch state {
    case "completed", "waiting": finish(id, success: true)
    case "failed": finish(id, success: false)
    default: break
    }
  }

  private func expire(_ id: String) {
    guard work[id] != nil else { return }
    finish(id, success: false)
    debugState = "expired"
  }

  public func finish(_ id: String, success: Bool) {
    guard let current = work.removeValue(forKey: id) else { return }
    LodyHosting.current?.endSendAllowance(current.token)
    debugState = success ? "completed" : "stopped"
  }

  public func finishAll(owner: String) {
    for (id, current) in work where current.owner == owner { finish(id, success: false) }
  }
}
