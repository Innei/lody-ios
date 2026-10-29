import LodyData

enum MacNotificationDecision: Equatable, Sendable {
  case permission(sessionId: String, title: String)
  case finished(sessionId: String, title: String)
}

@MainActor
enum MacNotificationDecider {
  static func decide(previous: SessionCatalog?, next: SessionCatalog, onScreen: String?) -> [MacNotificationDecision] {
    guard let previous else { return [] }
    return next.sessions.compactMap { session in
      guard session.id != onScreen, !session.archived, let before = previous.session(session.id) else { return nil }
      if before.awaitingUserSince == nil, session.awaitingUserSince != nil {
        return .permission(sessionId: session.id, title: session.title)
      }
      if MacSessionStatus.busy(before.status), !MacSessionStatus.busy(session.status), session.awaitingUserSince == nil {
        return .finished(sessionId: session.id, title: session.title)
      }
      return nil
    }
  }
}
