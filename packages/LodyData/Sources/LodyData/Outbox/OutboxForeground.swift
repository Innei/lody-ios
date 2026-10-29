import Foundation

public struct OutboxForeground: Equatable, Sendable {
  public enum Route: Equatable { case direct, guide, queue }

  public var live = false
  public var overflow = false
  public var serverCreated = false
  public var steerable = false
  public var promptBusy = false
  public var queuedMessageBehavior = "queue"
  public var transcript = SessionTranscriptFacts()

  public static func route(promptBusy: Bool, unfinishedTurn: Bool, behavior: String) -> Route {
    if promptBusy, behavior == "guide", unfinishedTurn { return .guide }
    if promptBusy || unfinishedTurn { return .queue }
    return .direct
  }

  public func plan(_ send: [String: OutboxValue]) -> (queue: Bool, guide: Bool) {
    let busy = send["queue"] == .bool(true) || promptBusy
    let route = Self.route(promptBusy: busy, unfinishedTurn: transcript.unfinishedTurnId != nil, behavior: queuedMessageBehavior)
    var requested = route == .guide
    if case .bool(let value)? = send["guide"] { requested = value }
    let guide = requested && steerable
    return (!guide && route != .direct, guide)
  }

  public static func statusKey(_ send: [String: OutboxValue], live: Bool) -> String {
    var attachments = false
    if case .array(let items)? = send["attachments"] { attachments = !items.isEmpty }
    let guide = send["guide"]?.truthy == true
    switch send["phase"]?.string ?? "" {
    case "failed": return "native.chat.message.retry"
    case "queued": return "native.chat.row.queued"
    case "unknown": return "send.status.unknown"
    case "creating": return "send.status.creating"
    case "sending": return attachments ? "send.status.uploading" : "send.status.sending"
    case "uploaded" where guide: return "native.chat.message.guide.confirming"
    case "accepted", "uploaded": return "send.status.waiting"
    default: return live ? "send.status.preparing" : "send.status.awaitingConnection"
    }
  }

  public init(live: Bool = false, overflow: Bool = false, serverCreated: Bool = false, steerable: Bool = false, promptBusy: Bool = false, queuedMessageBehavior: String = "queue", transcript: SessionTranscriptFacts = SessionTranscriptFacts()) {
    self.live = live
    self.overflow = overflow
    self.serverCreated = serverCreated
    self.steerable = steerable
    self.promptBusy = promptBusy
    self.queuedMessageBehavior = queuedMessageBehavior
    self.transcript = transcript
  }
}

public enum SessionQuota {
  public static let limit = 30
  public static let warning = 5

  public static func locked(count: Int?, tier: String?) -> Bool {
    guard tier == "free", let count else { return false }
    return count >= limit
  }

  public static func remaining(count: Int?, tier: String?) -> Int? {
    guard tier == "free", let count, count >= limit - warning else { return nil }
    return max(0, limit - count)
  }
}
