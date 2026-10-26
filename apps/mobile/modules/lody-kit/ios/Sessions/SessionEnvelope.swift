import Foundation

struct SessionEnvelope: Sendable {
  var version: Int?
  var revision: Int?
  var status = ""
  var overflow = false
  var entriesJSON = "[]"
  var billableTurnCount: Int?
  var composerJSON: String?
  var transcript = SessionTranscriptFacts()

  static func prepare(_ json: String) -> SessionEnvelope? {
    guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return nil }
    var envelope = SessionEnvelope(
      version: (object["v"] as? NSNumber)?.intValue, revision: (object["revision"] as? NSNumber)?.intValue,
      status: object["status"] as? String ?? "", overflow: object["overflow"] as? Bool == true
    )
    envelope.billableTurnCount = (object["billableTurnCount"] as? NSNumber)?.intValue
    if let composer = object["composer"] as? [String: Any], let data = try? JSONSerialization.data(withJSONObject: composer) {
      envelope.composerJSON = String(decoding: data, as: UTF8.self)
    }
    guard let entries = object["entries"] as? [[String: Any]] else { return envelope }
    envelope.transcript = SessionTranscriptFacts(entries: entries)
    let augmented = entries.map { entry in entry.merging(["fileDiffs": changedFiles(entry)]) { _, new in new } }
    if let data = try? JSONSerialization.data(withJSONObject: augmented) {
      envelope.entriesJSON = String(decoding: data, as: UTF8.self)
    }
    return envelope
  }

  static func changedFiles(_ entry: [String: Any]) -> [[String: Any]] {
    func count(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
    var order: [String] = []
    var files: [String: [String: Any]] = [:]
    let diffs = entry["fileDiffs"] as? [[String: Any]] ?? []
    let recorded = Set(diffs.compactMap { $0["path"] as? String })
    for diff in diffs {
      guard let path = diff["path"] as? String else { continue }
      if files[path] == nil { order.append(path) }
      files[path] = ["path": path, "add": count(diff["add"]), "del": count(diff["del"]), "status": "M"]
    }
    for item in entry["items"] as? [[String: Any]] ?? [] {
      guard item["type"] as? String == "tool_call", let path = item["path"] as? String, !path.isEmpty else { continue }
      let kind = item["kind"] as? String ?? ""
      guard kind != "read", kind != "search", !recorded.contains(path) else { continue }
      let status = ["delete": "D", "write": "A"][kind] ?? "M"
      if var existing = files[path] {
        existing["add"] = count(existing["add"]) + count(item["added"])
        existing["del"] = count(existing["del"]) + count(item["removed"])
        if status == "D" { existing["status"] = "D" }
        files[path] = existing
      } else {
        order.append(path)
        files[path] = ["path": path, "add": count(item["added"]), "del": count(item["removed"]), "status": status]
      }
    }
    return order.compactMap { files[$0] }
  }

  func accepted(generation: Int, after cursor: (generation: Int, revision: Int)) -> Bool {
    guard version == 1, generation >= cursor.generation else { return false }
    if generation > cursor.generation { return revision != nil }
    return (revision ?? .min) > cursor.revision
  }
}

struct SessionTranscriptFacts: Equatable, Sendable {
  var entryIds: Set<String> = []
  var replied: Set<String> = []
  var delivered: Set<String> = []
  var unfinishedTurnId: String?
  var conversational = false

  init() {}

  init(entries: [[String: Any]]) {
    var preceding: String?
    for entry in entries {
      guard let id = entry["id"] as? String else { continue }
      entryIds.insert(id)
      if let delivery = entry["delivery"] as? String, !delivery.isEmpty { delivered.insert(id) }
      switch entry["role"] as? String {
      case "user":
        preceding = id
        conversational = true
      case "assistant":
        conversational = true
        if let target = entry["userTurnId"] as? String ?? preceding { replied.insert(target) }
        if entry["finished"] as? Bool != true { unfinishedTurnId = id }
      default:
        break
      }
    }
  }
}
