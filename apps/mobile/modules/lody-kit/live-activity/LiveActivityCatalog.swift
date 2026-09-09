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
  }

  static let runningStatuses: Set<String> = ["running", "processing", "in_progress", "queued", "pending"]
  private static let glyphs = ["codex": "CX", "claude": "CC"]

  static func state(catalogJSON: String, labels: Labels) -> LodyActivityAttributes.ContentState {
    let root = (try? JSONSerialization.jsonObject(with: Data(catalogJSON.utf8))) as? [String: Any]
    let sessions = (root?["sessions"] as? [[String: Any]]) ?? []
    let requestedAt = Date().timeIntervalSince1970 * 1000
    let items = sessions.compactMap { item($0, labels: labels, requestedAt: requestedAt) }
    var counts = LodyActivityAttributes.ContentState.Counts()
    counts.permission = items.count { $0.status == .permission }
    counts.running = items.count { $0.status == .running }
    return LodyActivityAttributes.ContentState(
      totalCount: items.count,
      statusCounts: counts,
      items: items,
      permissionAlert: nil
    )
  }

  private static func item(_ session: [String: Any], labels: Labels, requestedAt: Double) -> Item? {
    guard let id = session["id"] as? String, session["archived"] as? Bool != true else { return nil }
    let awaiting = session["awaitingUserSince"] as? Double
    let status = resolveStatus(awaiting: awaiting, status: session["status"] as? String)
    guard let status else { return nil }
    let agent = session["agentType"] as? String ?? session["cliType"] as? String ?? ""
    let stamps = [awaiting, session["lastMessageAt"] as? Double].compactMap { $0 }
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
      updatedAtLabel: ""
    )
  }

  private static func resolveStatus(awaiting: Double?, status: String?) -> Item.Status? {
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
