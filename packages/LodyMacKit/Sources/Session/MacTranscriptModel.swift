import Foundation
import LodyData

enum MacTranscriptItem: Equatable {
  case user(id: String, text: String)
  case prose(id: String, markdown: String)
  case plan(id: String, markdown: String)
  case activity(id: String, symbol: String, text: String, attention: Bool, running: Bool)
  case changes(id: String, text: String)
  case notice(id: String, text: String)

  var id: String {
    switch self {
    case .user(let id, _), .prose(let id, _), .plan(let id, _), .changes(let id, _), .notice(let id, _): id
    case .activity(let id, _, _, _, _): id
    }
  }
}

struct MacTranscriptModel {
  var items: [MacTranscriptItem] = []
  var permission: SessionPermission?

  init(entriesJSON: String) {
    let data = Data(entriesJSON.utf8)
    guard let entries = try? JSONDecoder().decode([ChatEntry].self, from: data) else { return }
    let transcript = ChatTranscript(entries: entries)
    for row in transcript.rows() {
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
