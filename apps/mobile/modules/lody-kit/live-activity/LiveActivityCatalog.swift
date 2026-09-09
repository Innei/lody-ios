import Foundation

extension LodyActivityAttributes {
  static func activityId(workspaceId: String, userId: String) -> String {
    "lody-conversations:v5:\(workspaceId):\(userId)"
  }
}

enum LiveActivityCatalog {
  private typealias Item = LodyActivityAttributes.ContentState.Item

  private static let runningStatuses: Set<String> = ["running", "processing", "in_progress", "queued", "pending"]
  private static let statusLabels: [Item.Status: String] = [.permission: "需要你授权", .running: "正在工作"]
  private static let glyphs = ["codex": "CX", "claude": "CC"]

  static func state(catalogJSON: String) -> LodyActivityAttributes.ContentState {
    let root = (try? JSONSerialization.jsonObject(with: Data(catalogJSON.utf8))) as? [String: Any]
    let sessions = (root?["sessions"] as? [[String: Any]]) ?? []
    let items = sessions.compactMap(item)
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

  private static func item(_ session: [String: Any]) -> Item? {
    guard let id = session["id"] as? String else { return nil }
    let awaiting = session["awaitingUserSince"] as? Double
    let status = resolveStatus(awaiting: awaiting, status: session["status"] as? String)
    guard let status else { return nil }
    let agent = session["agentType"] as? String ?? session["cliType"] as? String ?? ""
    return Item(
      id: id,
      status: status,
      statusLabel: statusLabels[status] ?? "",
      permissionRequestId: nil,
      permissionCommand: nil,
      agentLogoKind: agent,
      agentLogoText: glyph(agent),
      title: session["title"] as? String ?? "",
      updatedAt: max(awaiting ?? 0, session["lastMessageAt"] as? Double ?? 0),
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
