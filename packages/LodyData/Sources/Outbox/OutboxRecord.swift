import Foundation
import LodyCore

public typealias OutboxValue = RuntimeContract.JSONValue

extension RuntimeContract.JSONValue {
  public var string: String? {
    if case .string(let value) = self { return value }
    return nil
  }

  public var object: [String: OutboxValue]? {
    if case .object(let value) = self { return value }
    return nil
  }

  public var truthy: Bool {
    switch self {
    case .null: return false
    case .bool(let value): return value
    case .number(let value): return value != 0 && !value.isNaN
    case .string(let value): return !value.isEmpty
    case .array, .object: return true
    }
  }
}

public struct OutboxRecord: Codable, Sendable, Equatable {
  public var session: [String: OutboxValue]
  public var send: [String: OutboxValue]

  public var sessionId: String { session["id"]?.string ?? "" }
  public var sendId: String { send["id"]?.string ?? "" }
  public var phase: String { send["phase"]?.string ?? "" }
  public var creation: String? { send["creation"]?.truthy == true ? send["creation"]?.string : nil }

  public func with(phase: String, reason: String? = nil, dropCreation: Bool = false) -> OutboxRecord {
    var next = self
    next.send["phase"] = .string(phase)
    if let reason { next.send["reason"] = .string(reason) }
    if dropCreation { next.send["creation"] = nil }
    return next
  }

  public static func restore(_ raw: String?, awaitingConfirmation: String) -> [OutboxRecord] {
    guard let raw, let saved = try? JSONDecoder().decode(OutboxValue.self, from: Data(raw.utf8)),
          case .array(let items) = saved else { return [] }
    return items.compactMap { item in
      guard let session = item.object?["session"]?.object, session["id"]?.truthy == true,
            let send = item.object?["send"]?.object, send["id"]?.truthy == true,
            send["text"]?.string != nil, case .array? = send["attachments"],
            send["choice"]?.truthy == true else { return nil }
      let record = OutboxRecord(session: session, send: send)
      guard record.phase == "creating" || record.phase == "sending" else { return record }
      return record.with(phase: "unknown", reason: awaitingConfirmation)
    }
  }

  public static func encode(_ records: [OutboxRecord]) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return (try? encoder.encode(records)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
  }

  public static func decode(_ json: String) -> OutboxRecord? {
    try? JSONDecoder().decode(OutboxRecord.self, from: Data(json.utf8))
  }

  public init(session: [String: OutboxValue], send: [String: OutboxValue]) {
    self.session = session
    self.send = send
  }
}
