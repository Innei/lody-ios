import Foundation
import LodyData

enum MacTranscriptItem: Hashable {
  case user(id: String, text: String)
  case prose(id: String, markdown: String)
  case plan(id: String, markdown: String)
  case activity(id: String, symbol: String, text: String, attention: Bool, running: Bool)
  case changes(id: String, text: String)
  case notice(id: String, text: String)
  case subagent(id: String, title: String, detail: String, running: Bool)
  case failedSend(id: String, text: String)

  var id: String {
    switch self {
    case .user(let id, _), .prose(let id, _), .plan(let id, _), .changes(let id, _), .notice(let id, _), .failedSend(let id, _): id
    case .subagent(let id, _, _, _): id
    case .activity(let id, _, _, _, _): id
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
        let names = row.attachments.map(\.fileName).joined(separator: ", ")
        items.append(.activity(id: row.id, symbol: "paperclip", text: names, attention: false, running: row.running))
      case "image":
        items.append(.activity(id: row.id, symbol: "photo", text: row.image?.fileName ?? "", attention: false, running: false))
      case "delivery":
        items.append(.activity(id: row.id, symbol: "clock", text: row.text, attention: row.attention, running: false))
      case "pending":
        items.append(.failedSend(id: row.id, text: row.text))
      default:
        continue
      }
    }
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
