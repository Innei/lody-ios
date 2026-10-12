import Foundation

enum RuntimeCommandPayload {
  private static let limits = [
    "providerCommand": 400 * 1024,
    "projectCommand": 1024 * 1024,
    "scheduleCommand": 832 * 1024,
    "queueMessage": 16 * 1024 * 1024,
    "sendTurn": 2 * 1024 * 1024,
    "editSession": 2 * 1024 * 1024,
    "checkTurnQuota": 2 * 1024 * 1024,
    "createSession": 2 * 1024 * 1024,
  ]

  static func decode(_ payload: String, method: String) -> [String: Any]? {
    // UTF-8 envelopes include escaped scripts/options, frozen Roles and queue receipts.
    let limit = limits[method] ?? 128 * 1024
    guard payload.utf8.count <= limit else { return nil }
    return try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
  }
}
