import ChatKitCore
import Foundation
import LodyData

struct MacAttachmentItem: Hashable {
  var id: String
  var name: String
  var bytes: Int?
  var image: Bool
  var media: CKMediaRef
  var progress: Double?

  var attachment: CKAttachment {
    CKAttachment(id: id, name: name, bytes: bytes, symbol: image ? "photo" : "doc", media: media, progress: progress)
  }
}

enum MacTranscriptItem: Hashable {
  case user(id: String, text: String)
  case prose(id: String, markdown: String)
  case plan(id: String, markdown: String)
  case activity(id: String, symbol: String, text: String, attention: Bool, running: Bool)
  case changes(id: String, text: String)
  case notice(id: String, text: String)
  case subagent(id: String, title: String, detail: String, running: Bool)
  case failedSend(id: String, text: String)
  case image(id: String, media: CKMediaRef, name: String, aspect: Double?)
  case attachments(id: String, files: [MacAttachmentItem])

  var id: String {
    switch self {
    case .user(let id, _), .prose(let id, _), .plan(let id, _), .changes(let id, _), .notice(let id, _), .failedSend(let id, _): id
    case .subagent(let id, _, _, _): id
    case .activity(let id, _, _, _, _): id
    case .image(let id, _, _, _), .attachments(let id, _): id
    }
  }

  var kind: String {
    switch self {
    case .user: "user"
    case .prose: "prose"
    case .plan: "plan"
    case .activity: "activity"
    case .changes: "changes"
    case .notice: "notice"
    case .subagent: "subagent"
    case .failedSend: "failedSend"
    case .image: "image"
    case .attachments: "attachments"
    }
  }
}

struct MacTranscriptModel {
  var items: [MacTranscriptItem] = []
  var groups: [String: String] = [:]
  var streaming = Set<String>()
  var permission: SessionPermission?

  struct Parsed {
    let json: String
    let entries: [ChatEntry]?
    let permission: SessionPermission?

    init(_ json: String) {
      self.json = json
      let data = Data(json.utf8)
      entries = try? JSONDecoder().decode([ChatEntry].self, from: data)
      let raw = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
      permission = entries == nil ? nil : try? SessionPermission.first(in: raw)
    }
  }

  init(entriesJSON: String, pendingJSON: String = "") {
    self.init(parsed: Parsed(entriesJSON), pendingJSON: pendingJSON)
  }

  init(parsed: Parsed, pendingJSON: String = "") {
    guard let entries = parsed.entries else { return }
    permission = parsed.permission
    let transcript = ChatTranscript(entries: entries)
    var rows = transcript.rows()
    if let pending = try? JSONDecoder().decode(ChatPendingSend.self, from: Data(pendingJSON.utf8)) {
      rows += pending.rows(entries: entries)
    }
    for row in rows {
      let before = items.count
      defer {
        for item in items[before...] {
          groups[item.id] = row.entryID
          if row.streaming { streaming.insert(item.id) }
        }
      }
      switch row.kind {
      case "user":
        items.append(.user(id: row.id, text: row.text))
      case "text":
        items.append(.prose(id: row.id, markdown: row.text))
      case "proposed_plan":
        items.append(.plan(id: row.id, markdown: row.text))
      case "summary":
        let process = transcript.rows(processEntryID: row.entryID)
        if process.isEmpty {
          items.append(Self.activity(row))
        } else {
          items += process.map(Self.processItem)
        }
      case "changes":
        items.append(.changes(id: row.id, text: row.text))
      case "chat_failed":
        items.append(.notice(id: row.id, text: row.text))
      case "subagent_task":
        let card = row.subagent
        let title = [card?.actor, card?.description].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        items.append(.subagent(id: row.id, title: title.isEmpty ? row.text : title, detail: card?.detail ?? "", running: row.running))
      case "attachments":
        items.append(.attachments(id: row.id, files: row.attachments.map { Self.attachment($0, progress: row.uploadProgress) }))
      case "image":
        guard let image = row.image else { continue }
        let aspect = image.width.flatMap { width in image.height.map { width / max($0, 1) } }
        items.append(.image(id: row.id, media: Self.media(image), name: image.fileName, aspect: aspect))
      case "delivery":
        items.append(.activity(id: row.id, symbol: "clock", text: row.text, attention: row.attention, running: false))
      case "pending":
        items.append(.failedSend(id: row.id, text: row.text))
      default:
        continue
      }
    }
  }

  static func media(_ image: ChatImage) -> CKMediaRef {
    CKMediaRef(id: image.id, context: ["kind": "image", "name": image.fileName, "session": image.storageSessionId ?? ""])
  }

  static func attachment(_ file: ChatMessageAttachment, progress: [String: ChatAttachmentUploadProgress]) -> MacAttachmentItem {
    var context = ["kind": file.image == nil ? "file" : "image", "name": file.fileName, "session": file.storageSessionId ?? ""]
    if let local = file.localURI { context["local"] = local }
    if let size = file.sizeBytes { context["size"] = String(size) }
    let state = progress[file.localID ?? file.id]
    let fraction = state.flatMap { $0.phase == "complete" ? nil : Double($0.percent ?? 0) / 100 }
    return MacAttachmentItem(
      id: file.id, name: file.fileName, bytes: file.sizeBytes, image: file.image != nil,
      media: CKMediaRef(id: file.image?.id ?? file.id, context: context), progress: fraction
    )
  }

  private static func processItem(_ row: ChatRow) -> MacTranscriptItem {
    switch row.kind {
    case "text": .prose(id: row.id, markdown: row.text)
    case "proposed_plan": .plan(id: row.id, markdown: row.text)
    default: activity(row)
    }
  }

  private static func activity(_ row: ChatRow) -> MacTranscriptItem {
    let symbol = row.symbol.isEmpty || row.symbol == "circle.fill" ? "wrench.and.screwdriver" : row.symbol
    return .activity(id: row.id, symbol: symbol, text: row.text, attention: row.attention, running: row.running)
  }
}
