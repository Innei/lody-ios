import CoreGraphics
import Foundation

public struct ChatFileDiff: Decodable, Equatable, Sendable {
  public let path: String
  public let add: Int?
  public let del: Int?
  public let status: String?

  public init(path: String, add: Int?, del: Int?, status: String?) {
    self.path = path
    self.add = add
    self.del = del
    self.status = status
  }
}

public struct ChatEntry: Decodable, Sendable {
  public struct ModelInfo: Decodable, Sendable {
    public let modelId: String?
    public let name: String?
    public let thoughtLevel: String?

    public var title: String {
      let name = self.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let model = name.isEmpty ? (modelId ?? "") : name
      return [model, thoughtLevel ?? ""]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    public init(modelId: String?, name: String?, thoughtLevel: String?) {
      self.modelId = modelId
      self.name = name
      self.thoughtLevel = thoughtLevel
    }
  }
  public let id: String
  public let role: String
  public let status: String
  public var finished: Bool
  public let timestamp: String?
  public let endedAt: Double?
  public let startedAt: Double?
  public var permissionWaitMs: Double? = nil
  public var items: [ChatItem]
  public let fileDiffs: [ChatFileDiff]?
  public var inputConfig: ChatTurnInput? = nil
  public var tokenUsage: ChatTurnUsage? = nil
  public var modelInfo: ModelInfo? = nil
  public var userTurnId: String? = nil
  public var executionId: String? = nil
  public var executionFinished: Bool? = nil
  public var steerCount: Int? = nil
  public var delivery: String? = nil
  public var holdOpen: Bool? = nil
  public var canSteer: Bool? = nil
  public var isRunning: Bool { role == "assistant" && !finished }
  public var isQueued: Bool { role == "user" && status == "queued" }

  public init(id: String, role: String, status: String, finished: Bool, timestamp: String?, endedAt: Double?, startedAt: Double?, permissionWaitMs: Double? = nil, items: [ChatItem], fileDiffs: [ChatFileDiff]?, inputConfig: ChatTurnInput? = nil, tokenUsage: ChatTurnUsage? = nil, modelInfo: ModelInfo? = nil, userTurnId: String? = nil, executionId: String? = nil, executionFinished: Bool? = nil, steerCount: Int? = nil, delivery: String? = nil, holdOpen: Bool? = nil, canSteer: Bool? = nil) {
    self.id = id
    self.role = role
    self.status = status
    self.finished = finished
    self.timestamp = timestamp
    self.endedAt = endedAt
    self.startedAt = startedAt
    self.permissionWaitMs = permissionWaitMs
    self.items = items
    self.fileDiffs = fileDiffs
    self.inputConfig = inputConfig
    self.tokenUsage = tokenUsage
    self.modelInfo = modelInfo
    self.userTurnId = userTurnId
    self.executionId = executionId
    self.executionFinished = executionFinished
    self.steerCount = steerCount
    self.delivery = delivery
    self.holdOpen = holdOpen
    self.canSteer = canSteer
  }
}

public struct ChatImage: Codable, Equatable, Sendable {
  public let id: String
  public let fileName: String
  public let storageSessionId: String?
  public let width: Double?
  public let height: Double?

  public init(id: String, fileName: String, storageSessionId: String?, width: Double?, height: Double?) {
    self.id = id
    self.fileName = fileName
    self.storageSessionId = storageSessionId
    self.width = width
    self.height = height
  }
}

public struct ChatMessageAttachment: Decodable, Equatable, Sendable {
  public let id: String
  public let fileName: String
  public var image: ChatImage? = nil
  public var localURI: String? = nil
  public var localID: String? = nil
  public var storageSessionId: String? = nil
  public var transport: String? = nil
  public var sizeBytes: Int? = nil

  public init(id: String, fileName: String, image: ChatImage? = nil, localURI: String? = nil, localID: String? = nil, storageSessionId: String? = nil, transport: String? = nil, sizeBytes: Int? = nil) {
    self.id = id
    self.fileName = fileName
    self.image = image
    self.localURI = localURI
    self.localID = localID
    self.storageSessionId = storageSessionId
    self.transport = transport
    self.sizeBytes = sizeBytes
  }
}

public struct ChatItem: Decodable, Sendable {
  public struct Permission: Decodable, Sendable { public let requestId: String; public let pending: Bool }
  public struct Plan: Decodable, Sendable { public let content: String; public let status: String }
  public struct NoticeMeta: Decodable, Equatable, Sendable { public let reason: String?; public let code: String?; public let message: String? }
  public var meta: NoticeMeta? = nil
  public var isChatFailure: Bool { type == "system_notice" && name == "chat_failed" }
  public let itemId: String
  public let type: String
  public let name: String?
  public var text: String?
  public let kind: String?
  public let title: String?
  public let status: String?
  public let path: String?
  public let hasDetail: Bool?
  public let permission: Permission?
  public let entries: [Plan]?
  public let description: String?
  public let actor: String?
  public var markdown: String? = nil
  public var isLatest: Bool? = nil
  public var lastToolName: String? = nil
  public var summary: String? = nil
  public var error: String? = nil
  public var isBackgrounded: Bool? = nil
  public var skipTranscript: Bool? = nil
  public var processDurationMs: Int? = nil
  public var isProcess: Bool { type != "text" && type != "proposed_plan" && !isAttachment && !isChatFailure && type != "subagent_task" }
  public var hidesFromTranscript: Bool {
    if type == "proposed_plan" {
      return !["delta", "completed"].contains(status ?? "") || (markdown ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return type == "subagent_task" && skipTranscript == true
  }
  public var isLiveSubagent: Bool {
    type == "subagent_task" && skipTranscript != true && (status == "in_progress" || status == "pending")
  }
  public let image: ChatImage?
  public var file: ChatMessageAttachment? = nil
  public var images: [ChatImage]? = nil
  public var isImage: Bool { type == "image" || type == "image_group" }
  public var isAttachment: Bool { isImage || type == "file" }

  public init(meta: NoticeMeta? = nil, itemId: String, type: String, name: String?, text: String? = nil, kind: String?, title: String?, status: String?, path: String?, hasDetail: Bool?, permission: Permission?, entries: [Plan]?, description: String?, actor: String?, markdown: String? = nil, isLatest: Bool? = nil, lastToolName: String? = nil, summary: String? = nil, error: String? = nil, isBackgrounded: Bool? = nil, skipTranscript: Bool? = nil, processDurationMs: Int? = nil, image: ChatImage?, file: ChatMessageAttachment? = nil, images: [ChatImage]? = nil) {
    self.meta = meta
    self.itemId = itemId
    self.type = type
    self.name = name
    self.text = text
    self.kind = kind
    self.title = title
    self.status = status
    self.path = path
    self.hasDetail = hasDetail
    self.permission = permission
    self.entries = entries
    self.description = description
    self.actor = actor
    self.markdown = markdown
    self.isLatest = isLatest
    self.lastToolName = lastToolName
    self.summary = summary
    self.error = error
    self.isBackgrounded = isBackgrounded
    self.skipTranscript = skipTranscript
    self.processDurationMs = processDurationMs
    self.image = image
    self.file = file
    self.images = images
  }
}

public struct ChatRow: Equatable, Sendable {
  public let id: String
  public let entryID: String
  public var kind: String
  public var text: String
  public var errorMeta: ChatItem.NoticeMeta? = nil
  public var errorRetry: ChatErrorRetryState? = nil
  public var planIsLatest = true
  public var planPermissionItemID = ""
  public var planDecision: ChatPlanDecisionState? = nil
  public var symbol = ""
  public var itemID = ""
  public var processStartID = ""
  public var actionable = false
  public var running = false
  public var attention = false
  public var streaming = false
  public var localImageURI: String? = nil
  public var image: ChatImage? = nil
  public var file: ChatMessageAttachment? = nil
  public var fileDiff: ChatFileDiff? = nil
  public var attachments: [ChatMessageAttachment] = []
  public var uploadProgress: [String: ChatAttachmentUploadProgress] = [:]
  public var workDurationMs: Int? = nil
  public var imageAsset = ""
  public var subagent: ChatSubagentCard? = nil
  public var detail = ""
  public var treeChild = false
  public var treeLast = false
  public var treeDown = false
  public var parentLive = false
  public var shines: Bool { running && kind != "duration" }
  /// `only` / `first` / `middle` / `last` for consecutive file rows in one group.
  public var group = ""

  public init(id: String, entryID: String, kind: String, text: String, errorMeta: ChatItem.NoticeMeta? = nil, errorRetry: ChatErrorRetryState? = nil, planIsLatest: Bool = true, planPermissionItemID: String = "", planDecision: ChatPlanDecisionState? = nil, symbol: String = "", itemID: String = "", processStartID: String = "", actionable: Bool = false, running: Bool = false, attention: Bool = false, streaming: Bool = false, localImageURI: String? = nil, image: ChatImage? = nil, file: ChatMessageAttachment? = nil, fileDiff: ChatFileDiff? = nil, attachments: [ChatMessageAttachment] = [], uploadProgress: [String: ChatAttachmentUploadProgress] = [:], workDurationMs: Int? = nil, imageAsset: String = "", subagent: ChatSubagentCard? = nil, detail: String = "", treeChild: Bool = false, treeLast: Bool = false, treeDown: Bool = false, group: String = "") {
    self.id = id
    self.entryID = entryID
    self.kind = kind
    self.text = text
    self.errorMeta = errorMeta
    self.errorRetry = errorRetry
    self.planIsLatest = planIsLatest
    self.planPermissionItemID = planPermissionItemID
    self.planDecision = planDecision
    self.symbol = symbol
    self.itemID = itemID
    self.processStartID = processStartID
    self.actionable = actionable
    self.running = running
    self.attention = attention
    self.streaming = streaming
    self.localImageURI = localImageURI
    self.image = image
    self.file = file
    self.fileDiff = fileDiff
    self.attachments = attachments
    self.uploadProgress = uploadProgress
    self.workDurationMs = workDurationMs
    self.imageAsset = imageAsset
    self.subagent = subagent
    self.detail = detail
    self.treeChild = treeChild
    self.treeLast = treeLast
    self.treeDown = treeDown
    self.group = group
  }
}

public enum ChatMetaTime: Sendable {
  public static let relativeDayLimit = 7

  public static func label(_ endedAt: Double?, now: Double, calendar: Calendar = .current) -> String {
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

public enum ChatWorkDuration: Sendable {
  private static let fractionalTimestamp = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let timestamp = Date.ISO8601FormatStyle()

  public static func startMilliseconds(for entry: ChatEntry) -> Double? {
    let parsedTimestamp = entry.timestamp.flatMap {
      (try? fractionalTimestamp.parse($0)) ?? (try? timestamp.parse($0))
    }
    return parsedTimestamp.map { $0.timeIntervalSince1970 * 1000 } ?? entry.startedAt
  }

  public static func milliseconds(for entry: ChatEntry, now: Double, startOverride: Double? = nil) -> Int? {
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

  public static func needsTimer(_ rows: [ChatRow]) -> Bool {
    rows.contains { $0.kind == "duration" && $0.running && $0.workDurationMs != nil }
  }

  public static func format(
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

  public static func label(_ milliseconds: Int) -> String {
    format(
      milliseconds,
      hour: String(localized: "native.chat.duration.hour", bundle: .lodyData),
      minute: String(localized: "native.chat.duration.minute", bundle: .lodyData),
      second: String(localized: "native.chat.duration.second", bundle: .lodyData)
    )
  }

  public static func title(_ milliseconds: Int, running: Bool) -> String {
    let key = running ? "native.chat.transcript.status.workingFor" : "native.chat.transcript.status.workedFor"
    return String.localizedStringWithFormat(String(localized: String.LocalizationValue(key), bundle: .lodyData), label(milliseconds))
  }
}

/// Conversation stays readable on wide hosts; the scroll view itself stays full-bleed
/// so the vertical indicator remains on the screen edge.
public enum ChatReadingColumn: Sendable {
  public static let maximumWidth: CGFloat = 800
  public static let cellMargin: CGFloat = 16
  public static let sectionTop: CGFloat = 4
  public static let sectionBottom: CGFloat = 4

  public static func columnWidth(in collectionWidth: CGFloat) -> CGFloat {
    min(max(1, collectionWidth), maximumWidth)
  }

  public static func horizontalInset(in collectionWidth: CGFloat) -> CGFloat {
    (max(0, collectionWidth - columnWidth(in: collectionWidth)) / 2) + cellMargin
  }

  public static func itemWidth(in collectionWidth: CGFloat) -> CGFloat {
    max(1, collectionWidth - horizontalInset(in: collectionWidth) * 2)
  }
}

public enum ChatTranscriptPreviewMetrics: Sendable {
  public static let width: CGFloat = 320
  public static let sectionInset: CGFloat = 16
  public static let symbolGutter: CGFloat = 36

  public static func itemWidth(collectionWidth: CGFloat) -> CGFloat {
    let width = collectionWidth > 1 ? collectionWidth : Self.width
    return max(1, width - sectionInset * 2)
  }

  public static func textWidth(itemWidth: CGFloat, hasSymbol: Bool) -> CGFloat {
    if !hasSymbol { return itemWidth }
    return max(1, itemWidth - symbolGutter)
  }
}

/// Stable identities belong to the protocol, never to the streamed text.
public struct ChatTranscript: Sendable {
  public var entries: [ChatEntry] = []

  public func liveSubagentItems() -> [ChatItem] {
    entries.flatMap(\.items).filter(\.isLiveSubagent)
  }

  private struct CachedEnvelope: Decodable {
    public let entries: [ChatEntry]?
  }

  public static func previewRows(from cache: String) -> [ChatRow] {
    guard let data = cache.data(using: .utf8) else { return [] }
    if let envelope = try? JSONDecoder().decode(CachedEnvelope.self, from: data),
       let entries = envelope.entries {
      return ChatTranscript(entries: entries).rows().filter { $0.kind != "meta" && $0.kind != "turn" }
    }
    if let entries = try? JSONDecoder().decode([ChatEntry].self, from: data) {
      return ChatTranscript(entries: entries).rows().filter { $0.kind != "meta" && $0.kind != "turn" }
    }
    return []
  }

  /// Provider-proven continuation groups retain original row identities. Only
  /// the finished presentation moves user bubbles above the combined process.
  public func rows(
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
      return entryRows(processEntryID: processEntryID, processStartID: processStartID, now: now, turnStartedAt: turnStartedAt,
        flatItems: processStartID == "__subagent__")
    }
    let ordinary = Dictionary(grouping: entryRows(now: now, turnStartedAt: turnStartedAt), by: \.entryID)
    var emitted = Set<String>()
    return ChatTranscript.dividingTurns(entries.flatMap { entry -> [ChatRow] in
      if let groupID = entry.executionId, let members = groups[groupID],
         let tail = members.last(where: { $0.role == "assistant" }),
         tail.executionFinished == true, members.filter({ $0.role == "assistant" }).allSatisfy(\.finished), !executionResultIDs(tail).isEmpty {
        guard emitted.insert(groupID).inserted else { return [] }
        let users = members.filter { $0.role == "user" }.flatMap {
          ChatTranscript(entries: [$0]).entryRows(now: now)
        }
        let process = executionProcess(members)
        var result = users
        if !process.isEmpty {
          result.append(ChatRow(id: groupID + ":execution", entryID: tail.id, kind: "summary",
            text: String.localizedStringWithFormat(String(localized: "native.chat.transcript.execution", bundle: .lodyData), String(describing: String(tail.steerCount ?? 0))),
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
      var result = ChatTranscript(entries: [visible]).entryRows(now: now, turnStartedAt: turnStartedAt)
      if entry.finished && !visible.finished {
        result.removeAll { $0.kind == "duration" }
        for index in result.indices {
          result[index].streaming = false
          result[index].running = false
        }
      }
      // Preserve existing duration attribution for ordinary conversation rows.
      if entry.executionId == nil && entry.holdOpen != true {
        return ChatTranscript.hangSubagents(ordinary[entry.id] ?? [])
      }
      return ChatTranscript.hangSubagents(result)
    }, entries: entries, now: now)
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
      // Older cached projections omitted notice names. Neither these placeholders nor
      // agent warnings belong in the conversation's execution process.
      entry.items.removeAll { $0.hidesFromTranscript || ($0.type == "system_notice" && ($0.name == nil || $0.name == "agent_warning")) }
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
            text: String(localized: String.LocalizationValue(key), bundle: .lodyData), attention: delivery == "rejected" || delivery == "unknown"), at: 0)
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
        if flatItems {
          visible = entry.items.indices.filter { !entry.items[$0].hidesFromTranscript }
        } else if !processStartID.isEmpty, let start = entry.items.firstIndex(where: { $0.itemId == processStartID }) {
          let end = entry.items.indices.dropFirst(start + 1).first { entry.items[$0].type == "text" || entry.items[$0].type == "proposed_plan" || entry.items[$0].isAttachment } ?? entry.items.endIndex
          visible = Array(start..<end).filter { entry.items[$0].type != "proposed_plan" && !entry.items[$0].isAttachment && !entry.items[$0].isChatFailure && !entry.items[$0].hidesFromTranscript }
        } else {
          visible = entry.items.indices.filter { $0 != finalText && entry.items[$0].type != "proposed_plan" && !entry.items[$0].isAttachment && !entry.items[$0].hidesFromTranscript }
        }
      } else if entry.finished {
        let process = entry.items.indices.filter {
          $0 != finalText && entry.items[$0].type != "proposed_plan" && !entry.items[$0].isAttachment && !entry.items[$0].isChatFailure && entry.items[$0].type != "subagent_task"
        }
        if let first = process.first { groups[first] = process }
        visible = process.first.map { [$0] } ?? []
        if let finalText { visible.append(finalText) }
        visible.append(contentsOf: entry.items.indices.filter {
          entry.items[$0].type == "proposed_plan" || entry.items[$0].isAttachment || entry.items[$0].isChatFailure
            || (entry.items[$0].type == "subagent_task" && !entry.items[$0].hidesFromTranscript)
        })
        visible.sort()
      } else {
        for index in entry.items.indices {
          if entry.items[index].type == "subagent_task" {
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
      var absorbed: Int?
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
            text: ChatWorkDuration.title(duration, running: entry.isRunning),
            running: entry.isRunning,
            workDurationMs: duration
          )
          if entry.finished, let first = groups.keys.min(), let indices = groups[first] {
            let process = indices.map { entry.items[$0] }
            row.detail = ChatProcessSummary.title(items: process, running: false, includesThought: false)
            row.actionable = true
            row.attention = process.contains { $0.permission?.pending == true || $0.status == "failed" }
            absorbed = first
          } else if !entry.finished, entry.holdOpen != true, entry.executionId == nil,
                    let first = visible.first(where: { entry.items[$0].type != "subagent_task" }),
                    let indices = groups[first] {
            let process = indices.map { entry.items[$0] }
            let tail = entry.items.indices.last { !entry.items[$0].hidesFromTranscript }
            let live = entry.isRunning && indices.last == tail && process.first?.processDurationMs == nil
            row.detail = ChatProcessSummary.title(items: process, running: live)
            row.actionable = true
            row.processStartID = entry.items[first].itemId
            row.attention = process.contains { $0.permission?.pending == true || $0.status == "failed" }
            absorbed = first
          }
          result.append(row)
        }
      }
      for index in visible {
        if let indices = groups[index] {
          if index == absorbed { continue }
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
            title = ChatWorkDuration.title(duration, running: false)
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
        case "file":
          guard let file = item.file else { continue }
          row.file = file
          row.text = file.fileName
          row.symbol = "doc"
          row.actionable = true
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
          row.text = item.title.flatMap { $0.isEmpty ? nil : $0 } ?? item.path ?? String(localized: "native.chat.transcript.tool", bundle: .lodyData)
          if item.permission?.pending == true { row.text = String.localizedStringWithFormat(String(localized: "native.chat.transcript.pending", bundle: .lodyData), String(describing: row.text)) }
          else if item.status == "failed" { row.text = String.localizedStringWithFormat(String(localized: "native.chat.transcript.failed", bundle: .lodyData), String(describing: row.text)) }
          row.actionable = item.hasDetail == true || item.permission?.pending == true
        case "plan":
          row.text = (item.entries ?? []).map { planPrefix($0.status) + $0.content }.joined(separator: "\n")
        case "subagent_task":
          row = ChatTranscript.subagentRow(entry: entry, item: item)
        default:
          row.text = item.title ?? String(localized: "native.chat.transcript.event", bundle: .lodyData)
          row.symbol = "info.circle"
        }
        if !row.text.isEmpty { result.append(row) }
      }
      if entry.role == "assistant", entry.finished, !processOnly {
        let files = (entry.fileDiffs ?? []).filter { !$0.path.isEmpty }
        if files.count > 1 {
          let add = files.reduce(0) { $0 + ($1.add ?? 0) }
          let del = files.reduce(0) { $0 + ($1.del ?? 0) }
          var header = ChatRow(
            id: entry.id + ":changes", entryID: entry.id, kind: "changesHeader",
            text: String.localizedStringWithFormat(String(localized: "native.chat.transcript.fileCount", bundle: .lodyData), files.count),
            actionable: true,
            fileDiff: ChatFileDiff(path: "", add: add, del: del, status: nil)
          )
          header.group = "first"
          result.append(header)
        }
        for (index, file) in files.enumerated() {
          var row = ChatRow(
            id: entry.id + ":changes:" + file.path, entryID: entry.id, kind: "changes",
            text: file.path, actionable: true, fileDiff: file
          )
          if files.count == 1 {
            row.group = "only"
          } else {
            row.group = index == files.count - 1 ? "last" : "middle"
          }
          result.append(row)
        }
        let model = entry.modelInfo?.title ?? ""
        let finishedAt = ChatMetaTime.label(entry.endedAt, now: now)
        let meta = [model, finishedAt].filter { !$0.isEmpty }.joined(separator: " · ")
        if !meta.isEmpty || entry.items.contains(where: { $0.type == "text" || $0.isImage }) {
          var row = ChatRow(id: entry.id + ":meta", entryID: entry.id, kind: "meta", text: meta)
          row.imageAsset = LodyAgentIcon.asset(
            modelId: entry.modelInfo?.modelId, name: entry.modelInfo?.name
          ) ?? ""
          result.append(row)
        }
      }
      return result
    }
  }

  public init(entries: [ChatEntry] = []) {
    self.entries = entries
  }
}

extension ChatTranscript {
  public static func turnLabel(_ milliseconds: Double, now: Double, calendar: Calendar = .current) -> String {
    let date = Date(timeIntervalSince1970: milliseconds / 1000)
    let current = Date(timeIntervalSince1970: now / 1000)
    let time = date.formatted(date: .omitted, time: .shortened)
    if calendar.isDate(date, inSameDayAs: current) { return time }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: current), calendar.isDate(date, inSameDayAs: yesterday) {
      return String.localizedStringWithFormat(String(localized: "native.chat.turn.yesterday", bundle: .lodyData), time)
    }
    return date.formatted(date: .abbreviated, time: .shortened)
  }

  static func turnRow(entryID: String, at milliseconds: Double?, now: Double) -> ChatRow {
    ChatRow(id: entryID + ":turn", entryID: entryID, kind: "turn", text: milliseconds.map { turnLabel($0, now: now) } ?? "")
  }

  static func dividingTurns(_ rows: [ChatRow], entries: [ChatEntry], now: Double) -> [ChatRow] {
    let users = Dictionary(entries.filter { $0.role == "user" }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    var seen = Set<String>()
    var runs = Set<String>()
    var result: [ChatRow] = []
    for row in rows {
      if let entry = users[row.entryID], seen.insert(entry.id).inserted {
        let steer = entry.delivery != nil || entry.executionId.map { runs.contains($0) } == true
        if seen.count > 1, !steer {
          result.append(turnRow(entryID: entry.id, at: ChatWorkDuration.startMilliseconds(for: entry), now: now))
        }
        if let run = entry.executionId { runs.insert(run) }
      }
      result.append(row)
    }
    return result
  }

  public static func hangSubagents(_ rows: [ChatRow]) -> [ChatRow] {
    var tasks = rows.filter { $0.kind == "subagent_task" }
    var result = rows.filter { $0.kind != "subagent_task" }
    guard !tasks.isEmpty, let process = result.firstIndex(where: { $0.kind == "duration" }) else { return rows }
    for index in tasks.indices {
      tasks[index].treeChild = true
      tasks[index].treeLast = index == tasks.count - 1
      tasks[index].parentLive = result[process].running
    }
    result[process].treeDown = true
    result.insert(contentsOf: tasks, at: process + 1)
    return result
  }

  fileprivate static func subagentRow(entry: ChatEntry, item: ChatItem) -> ChatRow {
    let actor = item.actor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let description = item.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let tool = item.lastToolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let summary = item.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let error = item.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let running = item.status == "in_progress" || item.status == "pending"
    var detail = ""
    if item.status == "in_progress", !tool.isEmpty {
      detail = String.localizedStringWithFormat(String(localized: "native.chat.subagent.runningTool", bundle: .lodyData), String(describing: tool))
    } else if item.status == "completed" {
      detail = summary
    } else if item.status == "failed" {
      detail = error
    }
    let card = ChatSubagentCard(
      actor: actor.isEmpty ? String(localized: "native.chat.transcript.subtask", bundle: .lodyData) : actor,
      description: description == actor ? "" : description,
      status: item.status ?? "pending",
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
      attention: item.status == "failed"
    )
    row.symbol = "point.3.connected.trianglepath.dotted"
    row.actionable = true
    row.subagent = card
    return row
  }
}

public struct ChatSubagentCard: Equatable, Sendable {
  public var actor: String
  public var description: String
  public var status: String
  public var detail: String
  public var background: Bool

  public init(actor: String, description: String, status: String, detail: String, background: Bool) {
    self.actor = actor
    self.description = description
    self.status = status
    self.detail = detail
    self.background = background
  }
}

public enum ChatProcessSummary: Sendable {
  public static func mark(attention: Bool) -> String {
    attention ? "exclamationmark.triangle.fill" : "circle.fill"
  }

  public static func title(items: [ChatItem], running: Bool, includesThought: Bool = true) -> String {
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
      parts.append(String(localized: String.LocalizationValue(running
          ? "native.chat.transcript.activity.thinking"
          : "native.chat.transcript.activity.thought"), bundle: .lodyData))
    }
    add(&parts, "native.chat.transcript.activity.commands", commands)
    add(&parts, "native.chat.transcript.activity.readFiles", readPaths.count + readWithout)
    add(&parts, "native.chat.transcript.activity.editedFiles", editPaths.count + editWithout)
    add(&parts, "native.chat.transcript.activity.searches", searches)
    add(&parts, "native.chat.transcript.activity.fetches", fetches)
    add(&parts, "native.chat.transcript.activity.tools", others)
    if parts.isEmpty && includesThought {
      return String(localized: "native.chat.transcript.status.done", bundle: .lodyData)
    }
    return parts.joined(separator: " · ")
  }

  private static func add(_ parts: inout [String], _ key: String, _ count: Int) {
    guard count > 0 else { return }
    parts.append(String.localizedStringWithFormat(String(localized: String.LocalizationValue(key), bundle: .lodyData), count))
  }
}


private func planPrefix(_ status: String?) -> String {
  switch status {
  case "completed": return "✓ "
  case "in_progress": return "› "
  default: return "○ "
  }
}

extension ChatPendingSend {
  public static func deliveryIndex(in rows: [ChatRow], entryID: String) -> Int? {
    rows.firstIndex { $0.entryID == entryID && $0.kind != "turn" }
  }

  public static func merging(_ pending: [ChatRow], into projected: [ChatRow]) -> [ChatRow] {
    var result = projected
    for row in pending {
      if row.kind == "delivery", let index = deliveryIndex(in: result, entryID: row.entryID) {
        result.insert(row, at: index)
      } else {
        result.append(row)
      }
    }
    return result
  }

  public static func hidingStatus(_ rows: [ChatRow], inFlight: Set<String>) -> [ChatRow] {
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

  public func rows(entries: [ChatEntry]) -> [ChatRow] {
    let body = bodyRows(entries: entries)
    let opensTurn = guide != true && !entries.contains { $0.id == id } && entries.contains { $0.role == "user" }
    guard opensTurn, body.contains(where: { $0.kind == "user" || $0.kind == "attachments" }) else { return body }
    let now = Date().timeIntervalSince1970 * 1000
    return [ChatTranscript.turnRow(entryID: id, at: startedAt ?? now, now: now)] + body
  }

  private func bodyRows(entries: [ChatEntry]) -> [ChatRow] {
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
      let delivery = status.isEmpty ? String(localized: "send.status.awaitingConnection", bundle: .lodyData) : status
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
        text: ChatWorkDuration.title(duration, running: true),
        running: true,
        workDurationMs: duration
      ))
    }
    return result
  }
}

// Unknown reasons retain their payload in the detail page and use a localized fallback.
public enum ChatFailure: Sendable {
  public static func title(_ meta: ChatItem.NoticeMeta?) -> String {
    if meta?.code == "git_executable_not_found" {
      return String(localized: "native.chat.error.git_executable_not_found", bundle: .lodyData)
    }
    let known: Set<String> = ["unknown", "session_archived", "agent_type_mismatch", "session_init_failed", "session_restore_failed", "session_not_found", "memory_pressure", "acp_not_ready", "agent_disconnected", "agent_no_output", "turn_pre_prompt_failed", "message_delivery_failed", "machine_access_denied", "acp_auth_required", "acp_internal_error", "acp_upstream_api_error", "acp_provider_overloaded", "acp_session_storage_incompatible", "acp_resource_not_found", "acp_request_cancelled", "acp_method_not_found", "acp_invalid_params", "acp_invalid_request", "acp_parse_error", "acp_unknown_error"]
    let reason = meta?.reason ?? "unknown"
    return String(localized: String.LocalizationValue("native.chat.error." + (known.contains(reason) ? reason : "unknown")), bundle: .lodyData)
  }
}


public struct ChatErrorRetryState: Decodable, Equatable, Sendable {
  public let entryId: String
  public let itemId: String
  public let enabled: Bool
  public let pending: Bool
  public let visible: Bool
  public let message: String

  public init(entryId: String, itemId: String, enabled: Bool, pending: Bool, visible: Bool, message: String) {
    self.entryId = entryId
    self.itemId = itemId
    self.enabled = enabled
    self.pending = pending
    self.visible = visible
    self.message = message
  }
}

extension ChatFailure {
  public static func hasDetail(_ meta: ChatItem.NoticeMeta?) -> Bool {
    [meta?.message, meta?.code].contains { !($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }
  public static func summary(_ meta: ChatItem.NoticeMeta?) -> String {
    if meta?.code == "git_executable_not_found" { return String(localized: "native.chat.error.gitSummary", bundle: .lodyData) }
    let descriptions = ["acp_provider_overloaded": "capacitySummary", "acp_auth_required": "authSummary", "machine_access_denied": "accessSummary"]
    if let key = descriptions[meta?.reason ?? ""] { return String(localized: String.LocalizationValue("native.chat.error." + key), bundle: .lodyData) }
    let message = (meta?.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if message.isEmpty || message.hasPrefix("{") || message.hasPrefix("[") { return String(localized: "native.chat.error.summary", bundle: .lodyData) }
    return String(message.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").prefix(260))
  }
}

public struct ChatPlanDecisionState: Decodable, Equatable, Sendable {
  public let entryId: String
  public let itemId: String
  public let enabled: Bool
  public let pending: Bool
  public let message: String

  public init(entryId: String, itemId: String, enabled: Bool, pending: Bool, message: String) {
    self.entryId = entryId
    self.itemId = itemId
    self.enabled = enabled
    self.pending = pending
    self.message = message
  }
}
