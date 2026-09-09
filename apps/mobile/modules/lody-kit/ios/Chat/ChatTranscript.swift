import Foundation

struct ChatFileDiff: Decodable, Equatable {
  let path: String
  let add: Int?
  let del: Int?
  let status: String?
}

struct ChatEntry: Decodable {
  let id: String
  let role: String
  let status: String
  var finished: Bool
  let timestamp: String?
  let endedAt: Double?
  let startedAt: Double?
  var items: [ChatItem]
  let fileDiffs: [ChatFileDiff]?
  var canSteer: Bool? = nil
  var isRunning: Bool { role == "assistant" && !finished }
  var isQueued: Bool { role == "user" && status == "queued" }
}

struct ChatImage: Decodable, Equatable {
  let id: String
  let fileName: String
  let storageSessionId: String?
  let width: Double?
  let height: Double?
}

struct ChatItem: Decodable {
  struct Permission: Decodable { let requestId: String; let pending: Bool }
  struct Plan: Decodable { let content: String; let status: String }
  let itemId: String
  let type: String
  let name: String?
  var text: String?
  let kind: String?
  let title: String?
  let status: String?
  let path: String?
  let hasDetail: Bool?
  let permission: Permission?
  let entries: [Plan]?
  let description: String?
  let actor: String?
  let image: ChatImage?
}

struct ChatRow: Equatable {
  let id: String
  let entryID: String
  var kind: String
  var text: String
  var symbol = ""
  var itemID = ""
  var processStartID = ""
  var actionable = false
  var running = false
  var attention = false
  var streaming = false
  var localImageURI: String? = nil
  var image: ChatImage? = nil
  var fileDiff: ChatFileDiff? = nil
  var workDurationMs: Int? = nil
  var shines: Bool { kind == "summary" && running && !attention }
  /// `only` / `first` / `middle` / `last` for consecutive file rows in one group.
  var group = ""
}

enum ChatWorkDuration {
  private static let fractionalTimestamp: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
  private static let timestamp = ISO8601DateFormatter()

  static func startMilliseconds(for entry: ChatEntry) -> Double? {
    let parsedTimestamp = entry.timestamp.flatMap {
      fractionalTimestamp.date(from: $0) ?? timestamp.date(from: $0)
    }
    return parsedTimestamp.map { $0.timeIntervalSince1970 * 1000 } ?? entry.startedAt
  }

  static func milliseconds(for entry: ChatEntry, now: Double, startOverride: Double? = nil) -> Int? {
    let start = startOverride ?? startMilliseconds(for: entry)
    let end = entry.finished ? entry.endedAt : now
    guard let start, let end, start.isFinite, end.isFinite, end >= start,
          end - start <= Double(Int.max) else { return nil }
    return Int(end - start)
  }

  static func needsTimer(_ rows: [ChatRow]) -> Bool {
    rows.contains { $0.kind == "duration" && $0.running && $0.workDurationMs != nil }
  }

  static func format(
    _ milliseconds: Int,
    hour: String,
    minute: String,
    second: String
  ) -> String {
    guard milliseconds >= 0 else { return "" }
    let totalSeconds = milliseconds / 1000
    let hours = totalSeconds / 3600
    let minutes = totalSeconds % 3600 / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return "\(hours)\(hour) \(pad2(minutes))\(minute) \(pad2(seconds))\(second)"
    }
    if minutes > 0 {
      return "\(minutes)\(minute) \(pad2(seconds))\(second)"
    }
    return "\(seconds)\(second)"
  }

  private static func pad2(_ value: Int) -> String {
    value < 10 ? "0\(value)" : String(value)
  }
}

/// Stable identities belong to the protocol, never to the streamed text.
struct ChatTranscript {
  var entries: [ChatEntry] = []

  private struct CachedEnvelope: Decodable {
    let entries: [ChatEntry]?
  }

  static func previewRows(from cache: String) -> [ChatRow] {
    guard let data = cache.data(using: .utf8) else { return [] }
    if let envelope = try? JSONDecoder().decode(CachedEnvelope.self, from: data),
       let entries = envelope.entries {
      return ChatTranscript(entries: entries).rows()
    }
    if let entries = try? JSONDecoder().decode([ChatEntry].self, from: data) {
      return ChatTranscript(entries: entries).rows()
    }
    return []
  }

  func rows(
    processEntryID: String = "",
    processStartID: String = "",
    now: Double = Date().timeIntervalSince1970 * 1000,
    turnStartedAt: [String: Double] = [:]
  ) -> [ChatRow] {
    entries.enumerated().flatMap { entryIndex, source -> [ChatRow] in
      var entry = source
      // Older cached projections omitted notice names. Neither these placeholders nor
      // agent warnings belong in the conversation's execution process.
      entry.items.removeAll { $0.type == "system_notice" && ($0.name == nil || $0.name == "agent_warning") }
      let processOnly = !processEntryID.isEmpty
      if processOnly && entry.id != processEntryID { return [] }
      if entry.role == "user" {
        if processOnly || entry.isQueued { return [] }
        var result: [ChatRow] = []
        for item in entry.items where item.type == "image" {
          guard let image = item.image else { continue }
          result.append(ChatRow(id: result.isEmpty ? entry.id + ":user" : entry.id + ":" + item.itemId,
            entryID: entry.id, kind: "image", text: image.fileName, itemID: item.itemId, image: image))
        }
        let text = entry.items.compactMap { $0.type == "text" ? $0.text : nil }.joined(separator: "\n\n")
        if !text.isEmpty {
          result.append(ChatRow(id: entry.id + (result.isEmpty ? ":user" : ":user-text"), entryID: entry.id, kind: "user", text: text))
        }
        return result
      }
      let finalText = entry.items.lastIndex { $0.type == "text" && !($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      var visible: [Int] = []
      var groups: [Int: [Int]] = [:]
      if entry.role != "assistant" {
        if processOnly { return [] }
        visible = Array(entry.items.indices)
      } else if processOnly {
        if !processStartID.isEmpty, let start = entry.items.firstIndex(where: { $0.itemId == processStartID }) {
          let end = entry.items.indices.dropFirst(start + 1).first { entry.items[$0].type == "text" } ?? entry.items.endIndex
          visible = Array(start..<end)
        } else {
          visible = entry.items.indices.filter { $0 != finalText }
        }
      } else if entry.finished {
        let process = entry.items.indices.filter { $0 != finalText }
        if let first = process.first { groups[first] = process }
        visible = process.first.map { [$0] } ?? []
        if let finalText { visible.append(finalText) }
      } else {
        for index in entry.items.indices {
          if entry.items[index].type == "text" {
            visible.append(index)
          } else if let previous = visible.last, groups[previous] != nil {
            groups[previous]!.append(index)
          } else {
            groups[index] = [index]
            visible.append(index)
          }
        }
      }
      var result: [ChatRow] = []
      if entry.role == "assistant", !processOnly {
        let turn = entries[..<entryIndex].last { $0.role == "user" }
        let turnID = turn?.id ?? entry.id
        let start = turnStartedAt[turnID] ?? turn.flatMap(ChatWorkDuration.startMilliseconds)
        if let duration = ChatWorkDuration.milliseconds(for: entry, now: now, startOverride: start) {
          result.append(ChatRow(
            id: turnID + ":duration",
            entryID: entry.id,
            kind: "duration",
            text: workDurationTitle(duration, running: entry.isRunning),
            running: entry.isRunning,
            workDurationMs: duration
          ))
        }
      }
      for index in visible {
        if let indices = groups[index] {
          let process = indices.map { entry.items[$0] }
          let needsPermission = process.contains { $0.permission?.pending == true }
          let failed = process.contains { $0.status == "failed" }
          let running = entry.isRunning && indices.last == entry.items.indices.last
          let firstGroup = index == groups.keys.min()
          result.append(ChatRow(id: entry.id + ":process" + (firstGroup ? "" : ":" + entry.items[index].itemId), entryID: entry.id, kind: "summary",
            text: ChatProcessSummary.title(items: process, running: running),
            symbol: "circle.fill",
            processStartID: entry.finished ? "" : entry.items[index].itemId,
            actionable: true, running: running, attention: needsPermission || failed))
          continue
        }
        let item = entry.items[index]
        let attention = item.status == "failed" || item.permission?.pending == true
        var row = ChatRow(id: entry.id + ":" + item.itemId, entryID: entry.id,
          kind: item.type, text: item.text ?? "", itemID: item.itemId,
          running: entry.isRunning && item.status == "in_progress", attention: attention,
          streaming: entry.isRunning && (item.type == "text" || item.type == "thought"))
        switch item.type {
        case "text": break
        case "thought": row.symbol = "brain"
        case "tool_call":
          row.symbol = ["read": "doc.text.magnifyingglass", "search": "magnifyingglass", "edit": "square.and.pencil",
            "write": "square.and.pencil", "execute": "terminal", "bash": "terminal", "fetch": "globe"][item.kind ?? ""] ?? "wrench.and.screwdriver"
          row.text = item.title.flatMap { $0.isEmpty ? nil : $0 } ?? item.path ?? LodyStrings.text("native.chat.transcript.tool")
          if item.permission?.pending == true { row.text = LodyStrings.text("native.chat.transcript.pending", ["text": row.text]) }
          else if item.status == "failed" { row.text = LodyStrings.text("native.chat.transcript.failed", ["text": row.text]) }
          row.actionable = item.hasDetail == true || item.permission?.pending == true
        case "plan":
          row.text = (item.entries ?? []).map { planPrefix($0.status) + $0.content }.joined(separator: "\n")
        case "subagent_task":
          row.symbol = "person.2"
          row.text = item.description ?? item.actor ?? LodyStrings.text("native.chat.transcript.subtask")
          if item.status == "failed" { row.text = LodyStrings.text("native.chat.transcript.failed", ["text": row.text]) }
        default:
          row.text = item.title ?? LodyStrings.text("native.chat.transcript.event")
          row.symbol = "info.circle"
        }
        if !row.text.isEmpty { result.append(row) }
      }
      if entry.role == "assistant", entry.finished, !processOnly {
        let files = (entry.fileDiffs ?? []).filter { !$0.path.isEmpty }
        if !files.isEmpty {
          let add = files.reduce(0) { $0 + ($1.add ?? 0) }
          let del = files.reduce(0) { $0 + ($1.del ?? 0) }
          result.append(ChatRow(
            id: entry.id + ":changes", entryID: entry.id, kind: "changesHeader",
            text: LodyStrings.plural("native.chat.transcript.fileCount", files.count),
            fileDiff: ChatFileDiff(path: "", add: add, del: del, status: nil)
          ))
          for (index, file) in files.enumerated() {
            var row = ChatRow(
              id: entry.id + ":changes:" + file.path, entryID: entry.id, kind: "changes",
              text: file.path, symbol: "doc.text", actionable: true, fileDiff: file
            )
            row.group = fileGroup(index: index, count: files.count)
            result.append(row)
          }
        }
      }
      return result
    }
  }
}

enum ChatProcessSummary {
  static func title(items: [ChatItem], running: Bool) -> String {
    var readPaths = Set<String>()
    var editPaths = Set<String>()
    var readWithout = 0
    var editWithout = 0
    var commands = 0
    var searches = 0
    var fetches = 0
    var others = 0
    var hasThought = false
    for item in items {
      if item.type == "thought" || item.kind == "think" {
        hasThought = true
        continue
      }
      guard item.type == "tool_call" else { continue }
      switch item.kind {
      case "execute", "bash":
        commands += 1
      case "read":
        if let path = item.path, !path.isEmpty { readPaths.insert(path) }
        else { readWithout += 1 }
      case "edit", "write", "delete", "move":
        if let path = item.path, !path.isEmpty { editPaths.insert(path) }
        else { editWithout += 1 }
      case "search":
        searches += 1
      case "fetch":
        fetches += 1
      default:
        others += 1
      }
    }
    var parts: [String] = []
    if hasThought {
      parts.append(LodyStrings.text(
        running
          ? "native.chat.transcript.activity.thinking"
          : "native.chat.transcript.activity.thought"
      ))
    }
    add(&parts, "native.chat.transcript.activity.commands", commands)
    add(&parts, "native.chat.transcript.activity.readFiles", readPaths.count + readWithout)
    add(&parts, "native.chat.transcript.activity.editedFiles", editPaths.count + editWithout)
    add(&parts, "native.chat.transcript.activity.searches", searches)
    add(&parts, "native.chat.transcript.activity.fetches", fetches)
    add(&parts, "native.chat.transcript.activity.tools", others)
    if parts.isEmpty {
      return LodyStrings.text("native.chat.transcript.status.done")
    }
    return parts.joined(separator: " · ")
  }

  private static func add(_ parts: inout [String], _ key: String, _ count: Int) {
    guard count > 0 else { return }
    parts.append(LodyStrings.plural(key, count))
  }
}

private func workDurationTitle(_ milliseconds: Int, running: Bool) -> String {
  let duration = ChatWorkDuration.format(
    milliseconds,
    hour: LodyStrings.text("native.chat.duration.hour"),
    minute: LodyStrings.text("native.chat.duration.minute"),
    second: LodyStrings.text("native.chat.duration.second")
  )
  return LodyStrings.text(
    running ? "native.chat.transcript.status.workingFor" : "native.chat.transcript.status.workedFor",
    ["duration": duration]
  )
}

private func planPrefix(_ status: String?) -> String {
  switch status {
  case "completed": return "✓ "
  case "in_progress": return "› "
  default: return "○ "
  }
}

private func fileGroup(index: Int, count: Int) -> String {
  if count == 1 { return "only" }
  if index == 0 { return "first" }
  if index == count - 1 { return "last" }
  return "middle"
}

/// Local visual state uses the dispatch ID, so authoritative history takes its place.
struct ChatPendingSend: Decodable {
  struct Attachment: Decodable {
    let id: String
    let name: String
    let uri: String
    let kind: String
  }
  let id: String
  let text: String
  let attachments: [Attachment]
  let status: String
  var startedAt: Double? = nil
  var failed: Bool? = nil
  var reconnect: Bool? = nil
  var queue: Bool? = nil

  func rows(entries: [ChatEntry]) -> [ChatRow] {
    guard failed != true, queue != true, !entries.contains(where: { $0.id == id && $0.isQueued }) else { return [] }
    var result: [ChatRow] = []
    if !entries.contains(where: { $0.id == id }) {
      for attachment in attachments where attachment.kind == "image" {
        guard URL(string: attachment.uri)?.isFileURL == true else { continue }
        result.append(ChatRow(id: result.isEmpty ? id + ":user" : id + ":" + attachment.id,
          entryID: id, kind: "image", text: attachment.name, localImageURI: attachment.uri,
          image: ChatImage(id: attachment.id, fileName: attachment.name, storageSessionId: nil, width: nil, height: nil)))
      }
      let body = ([text] + attachments.filter { $0.kind != "image" }.map(\.name)).filter { !$0.isEmpty }.joined(separator: "\n")
      if !body.isEmpty {
        result.append(ChatRow(id: id + (result.isEmpty ? ":user" : ":user-text"), entryID: id, kind: "user", text: body))
      }
    }
    let acceptedIndex = entries.firstIndex { $0.id == id }
    let hasReply = acceptedIndex.map { entries.dropFirst($0 + 1).contains { $0.role == "assistant" } } ?? false
    if !hasReply {
      let now = Date().timeIntervalSince1970 * 1000
      let start = startedAt.flatMap { $0.isFinite && $0 <= now ? $0 : nil } ?? now
      let duration = Int(now - start)
      result.append(ChatRow(
        id: id + ":duration",
        entryID: id,
        kind: "duration",
        text: workDurationTitle(duration, running: true),
        actionable: reconnect == true,
        running: true,
        workDurationMs: duration
      ))
    }
    return result
  }
}
