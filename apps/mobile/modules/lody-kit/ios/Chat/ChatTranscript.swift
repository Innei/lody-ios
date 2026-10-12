import CoreGraphics
import Foundation

struct ChatFileDiff: Decodable, Equatable {
  let path: String
  let add: Int?
  let del: Int?
  let status: String?
}

struct ChatTokenUsage: Decodable {
  let inputTokens: Int
  let outputTokens: Int
  let cacheReadInputTokens: Int
  let cacheCreationInputTokens: Int
  let reasoningOutputTokens: Int

  var total: Int? {
    var total = 0
    for count in [inputTokens, outputTokens, cacheReadInputTokens, cacheCreationInputTokens, reasoningOutputTokens] {
      guard count >= 0 else { return nil }
      let sum = total.addingReportingOverflow(count)
      guard !sum.overflow else { return nil }
      total = sum.partialValue
    }
    return total
  }
}

struct ChatMessageAuthor: Decodable {
  struct Role: Decodable { let name: String; let emoji: String }
  let kind: String
  let userId: String?
  let name: String?
  let role: Role?
}

struct ChatGoal: Decodable, Equatable {
  let threadId: String
  let objective: String
  let status: String
  let tokenBudget: Double?
  let tokensUsed: Double?
  let timeUsedSeconds: Double?
}

struct ChatContextWindowUsage: Decodable {
  let size: Double
  let used: Double
}

struct ChatQuota: Decodable {
  struct Window: Decodable {
    let label: String?
    let usedPercent: Double
    let duration: Double?
    let resetsAt: Double?
  }
  let id: String
  let name: String?
  let provider: String
  let windows: [Window]
}

struct ChatSubagentRun: Decodable {
  struct Snapshot: Decodable {
    struct Reason: Decodable { let message: String? }
    let state: String
    let name: String?
    let description: String?
    let summary: String?
    let reason: Reason?
  }
  struct Progress: Decodable { let summary: String?; let lastToolName: String? }
  let snapshot: Snapshot
  let progress: Progress?
}

struct ChatSessionContext: Decodable {
  var goal: ChatGoal? = nil
  var dismissedGoalThreadId: String? = nil
  var contextWindowUsage: ChatContextWindowUsage? = nil
  var quotas: [ChatQuota]? = nil
  var senders: [String: String]? = nil
  var showSenderIdentity: Bool? = nil
}

enum ChatUsage {
  static func number(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
  }

  static func summary(_ usage: ChatTokenUsage?) -> String {
    guard let total = usage?.total else { return "" }
    return summaryTokens(Double(total))
  }

  static func summaryTokens(_ total: Double) -> String {
    LodyStrings.text("native.chat.usage.tokens", ["count": number(total)])
  }
}

struct ChatEntry: Decodable {
  struct ModelInfo: Decodable {
    let modelId: String?
    let name: String?
    let thoughtLevel: String?

    var title: String {
      let name = self.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let model = name.isEmpty ? (modelId ?? "") : name
      return [model, thoughtLevel ?? ""]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }.joined(separator: " · ")
    }
  }
  let id: String
  let role: String
  let status: String
  var finished: Bool
  let timestamp: String?
  let endedAt: Double?
  let startedAt: Double?
  var permissionWaitMs: Double? = nil
  var items: [ChatItem]
  let fileDiffs: [ChatFileDiff]?
  var modelInfo: ModelInfo? = nil
  var userTurnId: String? = nil
  var executionId: String? = nil
  var executionFinished: Bool? = nil
  var steerCount: Int? = nil
  var delivery: String? = nil
  var holdOpen: Bool? = nil
  var canSteer: Bool? = nil
  var queueEditing: Bool? = nil
  var queueEditingStartedAt: Double? = nil
  var userId: String? = nil
  var author: ChatMessageAuthor? = nil
  var acpTurnId: String? = nil
  var tokenUsage: ChatTokenUsage? = nil
  var isRunning: Bool { role == "assistant" && !finished }
  var isQueued: Bool { role == "user" && status == "queued" }
}

struct ChatImage: Codable, Equatable {
  let id: String
  let fileName: String
  let storageSessionId: String?
  let width: Double?
  let height: Double?
}

struct ChatMessageAttachment: Decodable, Equatable {
  let id: String
  let fileName: String
  var image: ChatImage? = nil
  var localURI: String? = nil
  var localID: String? = nil
  var storageSessionId: String? = nil
  var transport: String? = nil
  var sizeBytes: Int? = nil
  var mimeType: String? = nil
  var textPreview: Bool? = nil
  var uploadedAt: Double? = nil
  var sourcePath: String? = nil
}

struct ChatItem: Decodable {
  struct Permission: Decodable { let requestId: String; let pending: Bool }
  struct Plan: Decodable { let content: String; let status: String }
  struct NoticeMeta: Decodable, Equatable {
    let reason: String?
    let code: String?
    let message: String?
    var source: String? = nil
    var sourceSessionId: String? = nil
    var sourceTitle: String? = nil
    var truncated: Bool? = nil
    var terminalOmitted: Bool? = nil
    var thinkingOmitted: Bool? = nil
  }
  var meta: NoticeMeta? = nil
  var isChatFailure: Bool { type == "system_notice" && name == "chat_failed" }
  var isNotice: Bool { type == "system_notice" || type == "agent_warning" }
  var isStandalone: Bool { type == "system_notice" || type == "agent_warning" || type == "subagent_task" }
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
  var markdown: String? = nil
  var isLatest: Bool? = nil
  var lastToolName: String? = nil
  var summary: String? = nil
  var error: String? = nil
  var isBackgrounded: Bool? = nil
  var skipTranscript: Bool? = nil
  var taskId: String? = nil
  var run: ChatSubagentRun? = nil
  var goal: ChatGoal? = nil
  var processDurationMs: Int? = nil
  var isProcess: Bool { type != "text" && type != "proposed_plan" && type != "goal" && !isAttachment && !isStandalone }
  var hidesFromTranscript: Bool {
    if type == "goal" { return true }
    if type == "proposed_plan" {
      return !["delta", "completed"].contains(status ?? "") || (markdown ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return type == "subagent_task" && skipTranscript == true
  }
  var isLiveSubagent: Bool {
    type == "subagent_task" && skipTranscript != true && (subagentStatus == "in_progress" || subagentStatus == "pending")
  }
  var subagentStatus: String {
    let state = run?.snapshot.state ?? status ?? "pending"
    return state == "running" ? "in_progress" : state
  }
  let image: ChatImage?
  var file: ChatMessageAttachment? = nil
  var images: [ChatImage]? = nil
  var isImage: Bool { type == "image" || type == "image_group" }
  var isAttachment: Bool { isImage || type == "file" }
}

struct ChatRow: Equatable {
  let id: String
  let entryID: String
  var kind: String
  var text: String
  var errorMeta: ChatItem.NoticeMeta? = nil
  var errorRetry: ChatErrorRetryState? = nil
  var planIsLatest = true
  var planPermissionItemID = ""
  var planDecision: ChatPlanDecisionState? = nil
  var symbol = ""
  var itemID = ""
  var processStartID = ""
  var actionable = false
  var running = false
  var attention = false
  var streaming = false
  var localImageURI: String? = nil
  var image: ChatImage? = nil
  var file: ChatMessageAttachment? = nil
  var fileDiff: ChatFileDiff? = nil
  var attachments: [ChatMessageAttachment] = []
  var uploadProgress: [String: ChatAttachmentUploadProgress] = [:]
  var workDurationMs: Int? = nil
  var imageAsset = ""
  var subagent: ChatSubagentCard? = nil
  var contextDetail = ""
  var shines: Bool { running && kind != "duration" }
  /// `only` / `first` / `middle` / `last` for consecutive file rows in one group.
  var group = ""
}

enum ChatMetaTime {
  static let relativeDayLimit = 7

  static func label(_ endedAt: Double?, now: Double, calendar: Calendar = .current) -> String {
    guard let endedAt, endedAt.isFinite, endedAt > 0, now.isFinite else { return "" }
    let ended = Date(timeIntervalSince1970: endedAt / 1000)
    let current = Date(timeIntervalSince1970: now / 1000)
    if calendar.isDate(ended, inSameDayAs: current) {
      return ended.formatted(date: .omitted, time: .shortened)
    }
    let days = calendar.dateComponents(
      [.day], from: calendar.startOfDay(for: ended), to: calendar.startOfDay(for: current)
    ).day
    guard let days, days >= 1, days < relativeDayLimit else {
      return ended.formatted(date: .abbreviated, time: .omitted)
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(from: DateComponents(day: -days))
  }
}

enum ChatWorkDuration {
  private static let fractionalTimestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let timestamp = Date.ISO8601FormatStyle()

  static func startMilliseconds(for entry: ChatEntry) -> Double? {
    let parsedTimestamp = entry.timestamp.flatMap {
      (try? fractionalTimestamp.parse($0)) ?? (try? timestamp.parse($0))
    }
    return parsedTimestamp.map { $0.timeIntervalSince1970 * 1000 } ?? entry.startedAt
  }

  static func milliseconds(for entry: ChatEntry, now: Double, startOverride: Double? = nil) -> Int? {
    let start = startOverride ?? startMilliseconds(for: entry)
    let end = entry.finished ? entry.endedAt : now
    guard let start, let end, start.isFinite, end.isFinite, end >= start,
          end - start <= Double(Int.max) else { return nil }
    var wait = 0.0
    if let written = entry.permissionWaitMs, written.isFinite, written > 0,
       written <= Double(Int.max)
    {
      wait = written
    }
    return Int(max(0, end - start - wait))
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

/// Conversation stays readable on wide hosts; the scroll view itself stays full-bleed
/// so the vertical indicator remains on the screen edge.
enum ChatReadingColumn {
  static let maximumWidth: CGFloat = 800
  static let cellMargin: CGFloat = 20
  static let sectionTop: CGFloat = 4
  static let sectionBottom: CGFloat = 4

  static func columnWidth(in collectionWidth: CGFloat) -> CGFloat {
    min(max(1, collectionWidth), maximumWidth)
  }

  static func horizontalInset(in collectionWidth: CGFloat) -> CGFloat {
    (max(0, collectionWidth - columnWidth(in: collectionWidth)) / 2) + cellMargin
  }

  static func itemWidth(in collectionWidth: CGFloat) -> CGFloat {
    max(1, collectionWidth - horizontalInset(in: collectionWidth) * 2)
  }
}

enum ChatTranscriptPreviewMetrics {
  static let width: CGFloat = 320
  static let sectionInset: CGFloat = 16
  static let symbolGutter: CGFloat = 36

  static func itemWidth(collectionWidth: CGFloat) -> CGFloat {
    let width = collectionWidth > 1 ? collectionWidth : Self.width
    return max(1, width - sectionInset * 2)
  }

  static func textWidth(itemWidth: CGFloat, hasSymbol: Bool) -> CGFloat {
    if !hasSymbol { return itemWidth }
    return max(1, itemWidth - symbolGutter)
  }
}

/// Stable identities belong to the protocol, never to the streamed text.
struct ChatTranscript {
  var entries: [ChatEntry] = []
  var senders: [String: String] = [:]
  var showSenderIdentity = false

  func liveSubagentItems() -> [ChatItem] {
    entries.flatMap(\.items).filter(\.isLiveSubagent)
  }

  private struct CachedEnvelope: Decodable {
    let entries: [ChatEntry]?
  }

  static func previewRows(from cache: String) -> [ChatRow] {
    guard let data = cache.data(using: .utf8) else { return [] }
    if let envelope = try? JSONDecoder().decode(CachedEnvelope.self, from: data),
       let entries = envelope.entries {
      return ChatTranscript(entries: entries).rows().filter { $0.kind != "meta" }
    }
    if let entries = try? JSONDecoder().decode([ChatEntry].self, from: data) {
      return ChatTranscript(entries: entries).rows().filter { $0.kind != "meta" }
    }
    return []
  }

  func readOnlyRows(now: Double = Date().timeIntervalSince1970 * 1000, turnStartedAt: [String: Double] = [:]) -> [ChatRow] {
    entryRows(now: now, turnStartedAt: turnStartedAt, flatItems: true)
  }

  /// Provider-proven continuation groups retain original row identities. Only
  /// the finished presentation moves user bubbles above the combined process.
  func rows(
    processEntryID: String = "",
    processStartID: String = "",
    now: Double = Date().timeIntervalSince1970 * 1000,
    turnStartedAt: [String: Double] = [:]
  ) -> [ChatRow] {
    if processStartID == "__tasks__" {
      return entries.flatMap { entry in
        entry.items.compactMap { item -> ChatRow? in
          guard item.type == "subagent_task", item.skipTranscript != true else { return nil }
          return ChatTranscript.subagentRow(entry: entry, item: item)
        }
      }
    }
    let groups = Dictionary(grouping: entries.filter { $0.executionId != nil }, by: { $0.executionId! })
    if processStartID == "__execution__",
       let groupID = entries.first(where: { $0.id == processEntryID })?.executionId,
       let members = groups[groupID] {
      return executionProcess(members)
    }
    if !processEntryID.isEmpty {
      return entryRows(processEntryID: processEntryID, processStartID: processStartID, now: now, turnStartedAt: turnStartedAt)
    }
    let ordinary = Dictionary(grouping: entryRows(now: now, turnStartedAt: turnStartedAt), by: \.entryID)
    var emitted = Set<String>()
    return entries.flatMap { entry -> [ChatRow] in
      if let groupID = entry.executionId, let members = groups[groupID],
         let tail = members.last(where: { $0.role == "assistant" }),
         tail.executionFinished == true, members.filter({ $0.role == "assistant" }).allSatisfy(\.finished), !executionResultIDs(tail).isEmpty {
        guard emitted.insert(groupID).inserted else { return [] }
        let users = members.filter { $0.role == "user" }.flatMap {
          ChatTranscript(entries: [$0], senders: senders, showSenderIdentity: showSenderIdentity).entryRows(now: now)
        }
        let process = executionProcess(members)
        var result = users
        if !process.isEmpty {
          result.append(ChatRow(id: groupID + ":execution", entryID: tail.id, kind: "summary",
            text: LodyStrings.text("native.chat.transcript.execution", ["count": String(tail.steerCount ?? 0)]),
            symbol: "circle.fill", processStartID: "__execution__", actionable: true))
        }
        result += members.filter { $0.role == "assistant" }.flatMap {
          ChatTranscript(entries: [$0]).entryRows(processEntryID: $0.id, flatItems: true).filter { $0.kind == "proposed_plan" }
        }
        let ids = executionResultIDs(tail)
        result += ChatTranscript(entries: [tail]).entryRows(processEntryID: tail.id, flatItems: true).filter { ids.contains($0.itemID) }
        result += ChatTranscript(entries: [tail]).entryRows(now: now).filter { ["meta", "changesHeader", "changes"].contains($0.kind) }
        return result
      }
      var visible = entry
      if entry.holdOpen == true || entry.executionId != nil { visible.finished = false }
      var result = ChatTranscript(entries: [visible], senders: senders, showSenderIdentity: showSenderIdentity).entryRows(now: now, turnStartedAt: turnStartedAt)
      if entry.finished && !visible.finished {
        result.removeAll { $0.kind == "duration" }
        for index in result.indices {
          result[index].streaming = false
          result[index].running = false
        }
      }
      // Preserve existing duration attribution for ordinary conversation rows.
      if entry.executionId == nil && entry.holdOpen != true {
        return ordinary[entry.id] ?? []
      }
      return result
    }
  }

  private func executionResultIDs(_ entry: ChatEntry) -> Set<String> {
    var result = Set<String>()
    for item in entry.items.reversed() {
      if item.isAttachment || (item.type == "text" && !(item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
        result.insert(item.itemId)
      } else { break }
    }
    return result
  }

  private func executionProcess(_ members: [ChatEntry]) -> [ChatRow] {
    let assistants = members.filter { $0.role == "assistant" }
    guard let tail = assistants.last else { return [] }
    let resultIDs = executionResultIDs(tail)
    return assistants.flatMap { entry in
      ChatTranscript(entries: [entry]).entryRows(processEntryID: entry.id, flatItems: true).filter {
        $0.kind != "proposed_plan" && (entry.id != tail.id || !resultIDs.contains($0.itemID))
      }
    }
  }

  private func entryRows(
    processEntryID: String = "",
    processStartID: String = "",
    now: Double = Date().timeIntervalSince1970 * 1000,
    turnStartedAt: [String: Double] = [:],
    flatItems: Bool = false
  ) -> [ChatRow] {
    entries.enumerated().flatMap { entryIndex, source -> [ChatRow] in
      var entry = source
      // Older cached projections omitted notice names and have no readable message.
      entry.items.removeAll { $0.hidesFromTranscript || ($0.type == "system_notice" && $0.name == nil && $0.meta?.message == nil) }
      let processOnly = !processEntryID.isEmpty
      if processOnly && entry.id != processEntryID { return [] }
      if entry.role == "user" {
        if processOnly || entry.isQueued { return [] }
        var result: [ChatRow] = []
        let attachments = entry.items.compactMap { item -> ChatMessageAttachment? in
          if let image = item.image, item.type == "image" {
            return ChatMessageAttachment(id: image.id, fileName: image.fileName, image: image)
          }
          return item.type == "file" ? item.file : nil
        }
        if !attachments.isEmpty {
          result.append(ChatRow(id: entry.id + ":user", entryID: entry.id, kind: "attachments", text: "", attachments: attachments))
        }
        let text = entry.items.compactMap { $0.type == "text" ? $0.text : nil }.joined(separator: "\n\n")
        if !text.isEmpty {
          result.append(ChatRow(id: entry.id + (result.isEmpty ? ":user" : ":user-text"), entryID: entry.id, kind: "user", text: text))
        }
        if let delivery = entry.delivery, delivery != "accepted" {
          let key = "native.chat.message.guide." + delivery
          result.insert(ChatRow(id: entry.id + ":delivery", entryID: entry.id, kind: "delivery",
            text: LodyStrings.text(key), attention: delivery == "rejected" || delivery == "unknown"), at: 0)
        }
        if let sender = senderRow(entry) { result.insert(sender, at: 0) }
        return result
      }
      let finalText = entry.items.lastIndex { $0.type == "text" && !($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      var visible: [Int] = []
      var groups: [Int: [Int]] = [:]
      if entry.role != "assistant" {
        if processOnly { return [] }
        visible = Array(entry.items.indices)
      } else if processOnly || flatItems {
        if flatItems {
          visible = entry.items.indices.filter { !entry.items[$0].hidesFromTranscript }
        } else if !processStartID.isEmpty, let start = entry.items.firstIndex(where: { $0.itemId == processStartID }) {
          let end = entry.items.indices.dropFirst(start + 1).first { entry.items[$0].type == "text" || entry.items[$0].type == "proposed_plan" || entry.items[$0].isAttachment || entry.items[$0].isStandalone } ?? entry.items.endIndex
          visible = Array(start..<end).filter { entry.items[$0].type != "proposed_plan" && !entry.items[$0].isAttachment && !entry.items[$0].isStandalone && !entry.items[$0].hidesFromTranscript }
        } else {
          visible = entry.items.indices.filter { $0 != finalText && entry.items[$0].type != "proposed_plan" && !entry.items[$0].isAttachment && !entry.items[$0].isNotice && !entry.items[$0].hidesFromTranscript }
        }
      } else if entry.finished {
        let process = entry.items.indices.filter {
          $0 != finalText && entry.items[$0].type != "proposed_plan" && !entry.items[$0].isAttachment && !entry.items[$0].isStandalone
        }
        if let first = process.first { groups[first] = process }
        visible = process.first.map { [$0] } ?? []
        if let finalText { visible.append(finalText) }
        visible.append(contentsOf: entry.items.indices.filter {
          entry.items[$0].type == "proposed_plan" || entry.items[$0].isAttachment || entry.items[$0].isStandalone
        })
        visible.sort()
      } else {
        for index in entry.items.indices {
          if entry.items[index].isStandalone {
            if !entry.items[index].hidesFromTranscript { visible.append(index) }
            continue
          }
          if entry.items[index].type == "text" || entry.items[index].type == "proposed_plan" || entry.items[index].isAttachment || entry.items[index].isChatFailure {
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
      var absorbedProcess = false
      if entry.role == "assistant", !processOnly {
        let turn: ChatEntry?
        if let userTurnID = entry.userTurnId {
          // A reply may arrive before its input; never borrow a neighboring turn's clock.
          turn = entries.first { $0.role == "user" && $0.id == userTurnID }
        } else {
          turn = entries[..<entryIndex].last { $0.role == "user" }
        }
        let turnID = entry.userTurnId ?? turn?.id ?? entry.id
        let start = turnStartedAt[turnID] ?? turn.flatMap(ChatWorkDuration.startMilliseconds)
        if let duration = ChatWorkDuration.milliseconds(for: entry, now: now, startOverride: start) {
          var row = ChatRow(
            id: turnID + ":duration",
            entryID: entry.id,
            kind: "duration",
            text: workDurationTitle(duration, running: entry.isRunning),
            running: entry.isRunning,
            workDurationMs: duration
          )
          if entry.finished, let first = groups.keys.min(), let indices = groups[first] {
            let process = indices.map { entry.items[$0] }
            let summary = ChatProcessSummary.title(items: process, running: false, includesThought: false)
            if !summary.isEmpty { row.text += " · " + summary }
            row.actionable = true
            row.attention = process.contains { $0.permission?.pending == true || $0.status == "failed" }
            absorbedProcess = true
          }
          result.append(row)
        }
      }
      for index in visible {
        if let indices = groups[index] {
          if absorbedProcess { continue }
          let process = indices.map { entry.items[$0] }
          let needsPermission = process.contains { $0.permission?.pending == true }
          let failed = process.contains { $0.status == "failed" }
          let tail = entry.items.indices.last { !entry.items[$0].hidesFromTranscript }
          let running = entry.isRunning && indices.last == tail && process.first?.processDurationMs == nil
          let firstGroup = index == groups.keys.min()
          let attention = needsPermission || failed
          var title = ChatProcessSummary.title(items: process, running: running)
          if !running, let duration = process.first?.processDurationMs {
            let summary = ChatProcessSummary.title(items: process, running: false, includesThought: false)
            title = workDurationTitle(duration, running: false)
            if !summary.isEmpty { title += " · " + summary }
          }
          result.append(ChatRow(id: entry.id + ":process" + (firstGroup ? "" : ":" + entry.items[index].itemId), entryID: entry.id, kind: "summary",
            text: title,
            symbol: ChatProcessSummary.mark(attention: attention),
            processStartID: entry.finished ? "" : entry.items[index].itemId,
            actionable: true, running: running, attention: attention))
          continue
        }
        let item = entry.items[index]
        if item.isImage {
          let images = item.type == "image" ? item.image.map { [$0] } ?? [] : item.images ?? []
          for (imageIndex, image) in images.enumerated() {
            result.append(ChatRow(id: entry.id + ":" + item.itemId + ":image:\(imageIndex)",
              entryID: entry.id, kind: "image", text: "", itemID: item.itemId, image: image))
          }
          continue
        }
        let attention = item.status == "failed" || item.permission?.pending == true
        var row = ChatRow(id: entry.id + ":" + item.itemId, entryID: entry.id,
          kind: item.type, text: item.text ?? "", itemID: item.itemId,
          running: entry.isRunning && item.status == "in_progress", attention: attention,
          streaming: entry.isRunning && (item.type == "text" || item.type == "thought"))
        switch item.type {
        case "system_notice" where item.isChatFailure:
          row.kind = "chat_failed"
          row.text = ChatFailure.title(item.meta)
          row.symbol = "exclamationmark.circle"
          row.attention = true
          row.errorMeta = item.meta
          row.actionable = false
        case "system_notice", "agent_warning":
          row.text = noticeText(item)
          row.symbol = item.name == "agent_warning" || item.type == "agent_warning" ? "exclamationmark.triangle" : "info.circle"
        case "file":
          guard let file = item.file else { continue }
          row.file = file
          row.text = file.fileName
          row.symbol = "doc"
          let expired = file.uploadedAt.map { now - $0 > 90 * 86_400_000 } ?? false
          row.actionable = file.transport != "local" && !expired
          if file.transport == "local" { row.text += " · " + LodyStrings.text("native.chat.file.uploading") }
          if expired { row.text += " · " + LodyStrings.text("native.chat.file.expired") }
          if let size = file.sizeBytes, size >= 0 {
            row.text += " · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
          }
        case "proposed_plan":
          row.text = item.markdown ?? ""
          row.streaming = item.status == "delta"
          row.planIsLatest = item.isLatest == true
          if row.planIsLatest {
            row.planPermissionItemID = entry.items.first {
              $0.type == "tool_call" && $0.kind == "switch_mode" && $0.permission?.pending == true
            }?.itemId ?? ""
          }
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
          row = ChatTranscript.subagentRow(entry: entry, item: item)
        default:
          row.text = item.title ?? LodyStrings.text("native.chat.transcript.event")
          row.symbol = "info.circle"
        }
        if !row.text.isEmpty { result.append(row) }
      }
      if entry.role == "assistant", entry.finished, !processOnly {
        let model = entry.modelInfo?.title ?? ""
        let finishedAt = ChatMetaTime.label(entry.endedAt, now: now)
        let meta = [model, finishedAt, ChatUsage.summary(entry.tokenUsage)].filter { !$0.isEmpty }.joined(separator: " · ")
        if !meta.isEmpty || entry.items.contains(where: { $0.type == "text" || $0.isImage }) {
          var row = ChatRow(id: entry.id + ":meta", entryID: entry.id, kind: "meta", text: meta)
          row.imageAsset = LodyAgentIcon.asset(
            modelId: entry.modelInfo?.modelId, name: entry.modelInfo?.name
          ) ?? ""
          result.append(row)
        }
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

extension ChatTranscript {
  func contextRows(_ context: ChatSessionContext, now: Double = Date().timeIntervalSince1970 * 1000) -> [ChatRow] {
    var rows: [ChatRow] = []
    let historyGoal = entries.reversed().lazy.compactMap { entry in
      entry.items.reversed().compactMap(\.goal).first
    }.first
    if let goal = historyGoal ?? context.goal, !goal.objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       !(goal.status == "cleared" && goal.threadId == context.dismissedGoalThreadId) {
      let key = "native.chat.goal." + goal.status
      var detail = goal.objective
      if let used = goal.tokensUsed, used.isFinite, used >= 0 {
        var metrics = ChatUsage.summaryTokens(used)
        if let budget = goal.tokenBudget, budget.isFinite, budget > 0 {
          metrics = LodyStrings.text("native.chat.goal.tokenBudget", ["used": ChatUsage.number(used), "budget": ChatUsage.number(budget)])
        }
        detail += "\n" + metrics
      }
      rows.append(ChatRow(id: "session-goal", entryID: "", kind: "goal", text: LodyStrings.text(key), symbol: "target", contextDetail: detail))
    }
    if let usage = context.contextWindowUsage, usage.size.isFinite, usage.size > 0, usage.used.isFinite, usage.used >= 0 {
      let percent = min(100, max(0, usage.used / usage.size * 100))
      rows.append(ChatRow(id: "session-context-usage", entryID: "", kind: "context", text: LodyStrings.text("native.chat.usage.context", ["percent": ChatUsage.number(percent)]), symbol: "chart.pie", contextDetail: LodyStrings.text("native.chat.usage.contextValue", ["used": ChatUsage.number(usage.used), "size": ChatUsage.number(usage.size)])))
    }
    for quota in context.quotas ?? [] {
      let windows = quota.windows.compactMap { window -> String? in
        guard window.usedPercent.isFinite else { return nil }
        let percent = ChatUsage.number(min(100, max(0, window.usedPercent)))
        var label = window.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if label.isEmpty, let duration = window.duration, duration.isFinite, duration > 0, duration < Double(Int.max) / 1000 {
          label = ChatWorkDuration.format(Int(duration * 1000), hour: LodyStrings.text("native.chat.duration.hour"), minute: LodyStrings.text("native.chat.duration.minute"), second: LodyStrings.text("native.chat.duration.second"))
        }
        if label.isEmpty { label = LodyStrings.text("native.chat.usage.quotaWindow") }
        var detail = LodyStrings.text("native.chat.usage.quota", ["window": label, "percent": percent])
        if let reset = window.resetsAt, reset.isFinite, reset > 0 {
          detail += " · " + LodyStrings.text("native.chat.usage.reset", ["time": Date(timeIntervalSince1970: reset).formatted(date: .abbreviated, time: .shortened)])
        }
        return detail
      }
      guard !windows.isEmpty else { continue }
      rows.append(ChatRow(id: "session-quota:" + quota.id, entryID: "", kind: "quota", text: quota.name ?? quota.provider, symbol: "gauge.with.dots.needle.50percent", contextDetail: windows.joined(separator: "\n")))
    }
    return rows
  }

  private func senderRow(_ entry: ChatEntry) -> ChatRow? {
    var name = ""
    if let author = entry.author, author.kind == "agent" {
      if let role = author.role { name = [role.emoji, role.name].filter { !$0.isEmpty }.joined(separator: " ") }
      else { name = author.name ?? "" }
    } else if showSenderIdentity && (entry.author == nil || entry.author?.kind == "human") {
      let id = entry.author?.userId ?? entry.userId ?? ""
      name = senders[id] ?? ""
    }
    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }
    return ChatRow(id: entry.id + ":sender", entryID: entry.id, kind: "sender", text: name, symbol: "person.crop.circle")
  }

  private func noticeText(_ item: ChatItem) -> String {
    let message = item.meta?.message ?? item.text ?? ""
    if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return message }
    if item.name == "resume_from_external_chat_history" {
      var text = LodyStrings.text("native.chat.notice.imported")
      if item.meta?.truncated == true { text += " · " + LodyStrings.text("native.chat.notice.truncated") }
      return text
    }
    if item.name == "session_fork_origin", let title = item.meta?.sourceTitle {
      return LodyStrings.text("native.chat.notice.fork", ["title": title])
    }
    return ""
  }

  fileprivate static func subagentRow(entry: ChatEntry, item: ChatItem) -> ChatRow {
    let status = item.subagentStatus
    let actor = (item.actor ?? item.run?.snapshot.name)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let description = (item.description ?? item.run?.snapshot.description)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let tool = (item.run?.progress?.lastToolName ?? item.lastToolName)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let summary = (item.run?.snapshot.summary ?? item.run?.progress?.summary ?? item.summary)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let error = (item.run?.snapshot.reason?.message ?? item.error)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let running = status == "in_progress" || status == "pending"
    var detail = ""
    if status == "in_progress", !tool.isEmpty {
      detail = LodyStrings.text("native.chat.subagent.runningTool", ["tool": tool])
    } else if status == "completed" {
      detail = summary
    } else if status == "failed" || status == "unknown" || status == "cancelled" {
      detail = error
    }
    let card = ChatSubagentCard(
      actor: actor.isEmpty ? LodyStrings.text("native.chat.transcript.subtask") : actor,
      description: description == actor ? "" : description,
      status: status,
      detail: detail,
      background: item.isBackgrounded == true
    )
    var row = ChatRow(
      id: entry.id + ":" + item.itemId,
      entryID: entry.id,
      kind: "subagent_task",
      text: [card.actor, card.description, detail].filter { !$0.isEmpty }.joined(separator: " · "),
      itemID: item.itemId,
      running: running,
      attention: status == "failed"
    )
    row.symbol = "person.2"
    row.actionable = true
    row.subagent = card
    return row
  }
}

struct ChatSubagentCard: Equatable {
  var actor: String
  var description: String
  var status: String
  var detail: String
  var background: Bool
}

enum ChatProcessSummary {
  static func mark(attention: Bool) -> String {
    attention ? "exclamationmark.triangle.fill" : "circle.fill"
  }

  static func title(items: [ChatItem], running: Bool, includesThought: Bool = true) -> String {
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
    if hasThought && includesThought {
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
    if parts.isEmpty && includesThought {
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

extension ChatPendingSend {
  static func hidingStatus(_ rows: [ChatRow], inFlight: Set<String>) -> [ChatRow] {
    guard !inFlight.isEmpty else { return rows }
    return rows.filter { row in
      switch row.kind {
      case "duration", "pending":
        return !inFlight.contains(row.entryID)
      default:
        return true
      }
    }
  }

  func rows(entries: [ChatEntry]) -> [ChatRow] {
    guard (queue != true || failed == true), !entries.contains(where: { $0.id == id && $0.isQueued }) else { return [] }
    var result: [ChatRow] = []
    if !entries.contains(where: { $0.id == id }) {
      let media = attachments.compactMap { attachment -> ChatMessageAttachment? in
        guard URL(string: attachment.uri)?.isFileURL == true else { return nil }
        let image = attachment.kind == "image"
          ? ChatImage(id: attachment.id, fileName: attachment.name, storageSessionId: nil, width: nil, height: nil)
          : nil
        return ChatMessageAttachment(id: attachment.id, fileName: attachment.name, image: image, localURI: attachment.uri)
      }
      if !media.isEmpty {
        result.append(ChatRow(id: id + ":user", entryID: id, kind: "attachments", text: status,
          running: failed != true && reconnect != true && !["accepted", "uploaded", "unknown"].contains(phase ?? ""),
          attachments: media, uploadProgress: uploadProgress ?? [:]))
      }
      let body = text
      if !body.isEmpty {
        result.append(ChatRow(id: id + (result.isEmpty ? ":user" : ":user-text"), entryID: id, kind: "user", text: body))
      }
    }
    if failed == true {
      result.append(ChatRow(id: id + ":pending", entryID: id, kind: "pending", text: status,
        actionable: true, attention: true))
      return result
    }
    var precedingUserID: String?
    let hasReply = entries.contains { entry in
      if entry.role == "user" { precedingUserID = entry.id }
      return entry.role == "assistant" && (entry.userTurnId ?? precedingUserID) == id
    }
    let hasDelivery = entries.contains { $0.id == id && $0.delivery != nil }
    let acknowledged = phase == "accepted"
    if !hasReply && !acknowledged && !hasDelivery {
      let delivery = status.isEmpty ? LodyStrings.text("send.status.awaitingConnection") : status
      result.insert(ChatRow(id: id + ":delivery", entryID: id, kind: "delivery", text: delivery,
        attention: phase == "unknown"), at: 0)
    }
    if !hasReply && acknowledged && !hasDelivery {
      let now = Date().timeIntervalSince1970 * 1000
      let start = startedAt.flatMap { $0.isFinite && $0 <= now ? $0 : nil } ?? now
      let duration = Int(now - start)
      result.append(ChatRow(
        id: id + ":duration",
        entryID: id,
        kind: "duration",
        text: workDurationTitle(duration, running: true),
        running: true,
        workDurationMs: duration
      ))
    }
    return result
  }
}

// Unknown reasons retain their payload in the detail page and use a localized fallback.
enum ChatFailure {
  static func title(_ meta: ChatItem.NoticeMeta?) -> String {
    if meta?.code == "git_executable_not_found" {
      return LodyStrings.text("native.chat.error.git_executable_not_found")
    }
    let known: Set<String> = ["unknown", "session_archived", "agent_type_mismatch", "session_init_failed", "session_restore_failed", "session_not_found", "memory_pressure", "acp_not_ready", "agent_disconnected", "agent_no_output", "turn_pre_prompt_failed", "message_delivery_failed", "machine_access_denied", "acp_auth_required", "acp_internal_error", "acp_upstream_api_error", "acp_provider_overloaded", "acp_session_storage_incompatible", "acp_resource_not_found", "acp_request_cancelled", "acp_method_not_found", "acp_invalid_params", "acp_invalid_request", "acp_parse_error", "acp_unknown_error"]
    let reason = meta?.reason ?? "unknown"
    return LodyStrings.text("native.chat.error." + (known.contains(reason) ? reason : "unknown"))
  }
}


struct ChatErrorRetryState: Decodable, Equatable {
  let entryId: String
  let itemId: String
  let enabled: Bool
  let pending: Bool
  let visible: Bool
  let message: String
}

extension ChatFailure {
  static func hasDetail(_ meta: ChatItem.NoticeMeta?) -> Bool {
    [meta?.message, meta?.code].contains { !($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }
  static func summary(_ meta: ChatItem.NoticeMeta?) -> String {
    if meta?.code == "git_executable_not_found" { return LodyStrings.text("native.chat.error.gitSummary") }
    let descriptions = ["acp_provider_overloaded": "capacitySummary", "acp_auth_required": "authSummary", "machine_access_denied": "accessSummary"]
    if let key = descriptions[meta?.reason ?? ""] { return LodyStrings.text("native.chat.error." + key) }
    let message = (meta?.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if message.isEmpty || message.hasPrefix("{") || message.hasPrefix("[") { return LodyStrings.text("native.chat.error.summary") }
    return String(message.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").prefix(260))
  }
}

struct ChatPlanDecisionState: Decodable, Equatable {
  let entryId: String
  let itemId: String
  let enabled: Bool
  let pending: Bool
  let message: String
}
