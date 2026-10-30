import Foundation

public enum SessionDeletion {
  public static func targets(_ sessions: [SessionItem], id: String) -> [SessionItem] {
    sessions.filter { $0.id == id || $0.parentSessionId == id }
  }

  public static func blocked(_ sessions: [SessionItem]) -> Bool {
    sessions.contains { !$0.archived && !["idle", "pending", "completed", "error"].contains($0.status) }
  }

  public static func removesWorktree(_ session: SessionItem) -> Bool {
    !session.projectId.hasSuffix(":unassigned")
  }
}
