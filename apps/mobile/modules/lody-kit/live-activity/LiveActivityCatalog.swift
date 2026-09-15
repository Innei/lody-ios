import Foundation

extension LodyActivityAttributes {
  static func activityId(workspaceId: String, userId: String) -> String {
    "lody-conversations:v5:\(workspaceId):\(userId)"
  }
}

enum LiveActivityCatalog {
  private typealias Item = LodyActivityAttributes.ContentState.Item

  struct Labels: Sendable {
    var permission: String
    var running: String
    var stale: String
    var empty: String
    var others: String
    var lastSync: String
    var openHint: String
    var runningSummary: String = "{count} running"
    var completedSummary: String = "{count} tasks finished"
    var completed: String = "Completed"
    var failed: String = "Failed"
    var failedSummary: String = "{count} tasks failed"
    var elapsed: String = "elapsed"
    var waiting: String = "waiting"
    var took: String = "took"
  }

  static let runningStatuses: Set<String> = ["running", "initializing", "processing", "in_progress", "queued"]
  private static let glyphs = ["codex": "CX", "claude": "CC"]

  static func state(catalogJSON: String, labels: Labels) -> LodyActivityAttributes.ContentState {
    let root = (try? JSONSerialization.jsonObject(with: Data(catalogJSON.utf8))) as? [String: Any]
    let sessions = (root?["sessions"] as? [[String: Any]]) ?? []
    return state(sessions: sessions, labels: labels)
  }

  static func state(sessions: [[String: Any]], labels: Labels) -> LodyActivityAttributes.ContentState {
    let requestedAt = Date().timeIntervalSince1970 * 1000
    let items = sessions.compactMap { item($0, labels: labels, requestedAt: requestedAt) }
    var counts = LodyActivityAttributes.ContentState.Counts()
    counts.permission = items.count { $0.status == .permission }
    counts.running = items.count { $0.status == .running }
    var copy = LodyActivityAttributes.ContentState.Copy(stale: labels.stale, empty: labels.empty, others: labels.others, lastSync: labels.lastSync, openHint: labels.openHint)
    copy.runningSummary = labels.runningSummary
    copy.completedSummary = labels.completedSummary
    copy.completedLabel = labels.completed
    copy.failedLabel = labels.failed
    copy.failedSummary = labels.failedSummary
    copy.elapsed = labels.elapsed
    copy.waiting = labels.waiting
    copy.took = labels.took
    return LodyActivityAttributes.ContentState(
      totalCount: items.count,
      statusCounts: counts,
      items: items,
      permissionAlert: nil,
      copy: copy
    )
  }

  static func failedSessionIds(sessions: [[String: Any]]) -> Set<String> {
    Set(sessions.compactMap { session in
      guard session["status"] as? String == "error", let id = session["id"] as? String else { return nil }
      return id
    })
  }

  private static func item(_ session: [String: Any], labels: Labels, requestedAt: Double) -> Item? {
    guard let id = session["id"] as? String, session["archived"] as? Bool != true else { return nil }
    let awaiting = session["awaitingUserSince"] as? Double
    let status = resolveStatus(awaiting: awaiting, status: session["status"] as? String)
    guard let status else { return nil }
    let agent = session["agentType"] as? String ?? session["cliType"] as? String ?? ""
    let lastMessageAt = session["lastMessageAt"] as? Double
    let stamps = [awaiting, lastMessageAt].compactMap { $0 }
    return Item(
      id: id,
      status: status,
      statusLabel: status == .permission ? labels.permission : labels.running,
      permissionRequestId: nil,
      permissionCommand: nil,
      agentLogoKind: agent,
      agentLogoText: glyph(agent),
      title: session["title"] as? String ?? "",
      updatedAt: stamps.max() ?? requestedAt,
      updatedAtLabel: "",
      startedAt: startedAt(status: status, awaiting: awaiting, lastRunningSeen: session["lastRunningSeen"] as? Double, lastMessageAt: lastMessageAt)
    )
  }

  // lastMessageAt is written when a turn completes, so a lastRunningSeen behind it
  // belongs to an earlier turn and must not seed this one's timer.
  static func startedAt(status: LodyActivityAttributes.ContentState.Item.Status, awaiting: Double?, lastRunningSeen: Double?, lastMessageAt: Double?) -> Double? {
    let turnStart = lastRunningSeen.flatMap { $0 >= (lastMessageAt ?? 0) ? $0 : nil }
    switch status {
    case .permission, .question: return awaiting ?? turnStart
    case .running: return turnStart
    case .unread, .failed: return nil
    }
  }

  private static func resolveStatus(awaiting: Double?, status: String?) -> Item.Status? {
    if ["completed", "error"].contains(status ?? "") { return nil }
    if status == "requestPermission" || status == "waiting" { return .permission }
    if awaiting != nil { return .permission }
    guard let status, runningStatuses.contains(status) else { return nil }
    return .running
  }

  private static func glyph(_ agent: String) -> String {
    if let known = glyphs[agent.lowercased()] { return known }
    let letters = agent.filter(\.isLetter).prefix(2).uppercased()
    return letters.isEmpty ? "AC" : letters
  }
}
