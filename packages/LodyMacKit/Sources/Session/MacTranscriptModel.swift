import Foundation
import LodyData

enum MacTranscriptItem: Equatable {
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
}

struct MacTranscriptModel {
  var items: [MacTranscriptItem] = []
  var permission: SessionPermission?

  init(entriesJSON: String, pendingJSON: String = "") {
    let data = Data(entriesJSON.utf8)
    guard let entries = try? JSONDecoder().decode([ChatEntry].self, from: data) else { return }
    let transcript = ChatTranscript(entries: entries)
    var rows = transcript.rows()
    if let pending = try? JSONDecoder().decode(ChatPendingSend.self, from: Data(pendingJSON.utf8)) {
      rows += pending.rows(entries: entries)
    }
    for row in rows {
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
          items += process.map(Self.activity)
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
    let raw = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
    permission = try? SessionPermission.first(in: raw)
  }

  private static func activity(_ row: ChatRow) -> MacTranscriptItem {
    let symbol = row.symbol.isEmpty || row.symbol == "circle.fill" ? "wrench.and.screwdriver" : row.symbol
    return .activity(id: row.id, symbol: symbol, text: row.text, attention: row.attention, running: row.running)
  }
}
