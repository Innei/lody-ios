import Foundation
import LodyData

@MainActor
final class MacTranscriptFixture {
  private var answered: String?
  private var replies: [String] = []
  private var changed: (@MainActor (SessionFeedState) -> Void)?

  var source: MacTranscriptSource {
    MacTranscriptSource(
      start: { [self] changed in
        self.changed = changed
        changed(state)
      },
      stop: { [self] in changed = nil },
      answer: { [self] _, optionId in
        answered = optionId
        changed?(state)
      }
    )
  }

  func reply(_ text: String) {
    replies.append(text)
    changed?(state)
  }

  private var state: SessionFeedState { SessionFeedState(status: "live", entriesJSON: json) }

  private var followUps: String {
    replies.enumerated().map { index, text in
      let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
      let quoted = String(decoding: data, as: UTF8.self).dropFirst().dropLast()
      return #",{"id":"r\#(index)","role":"user","status":"completed","finished":true,"items":[{"itemId":"t","type":"text","text":\#(quoted)}]}"#
    }.joined()
  }

  private var json: String {
    let permission = answered == nil
      ? #","permission":{"pending":true,"requestId":"r-edit","options":[{"optionId":"allow","name":"Allow","kind":"allow_once"},{"optionId":"deny","name":"Deny","kind":"reject_once"}]}"#
      : #","status":"completed""#
    let reply = answered == nil ? "" : #",{"itemId":"done","type":"text","text":"Approved. The sidebar now groups sessions by project, with **Pinned** on top."}"#
    return """
    [{"id":"u1","role":"user","status":"completed","finished":true,"items":[{"itemId":"q","type":"text","text":"Add a sidebar like the Codex desktop app: pinned sessions, then projects."}]},
     {"id":"a1","role":"assistant","status":"completed","finished":true,"items":[
      {"itemId":"think","type":"thought","text":"Reading the window shell first"},
      {"itemId":"read","type":"tool_call","kind":"read","title":"Read MainWindowController.swift","status":"completed"},
      {"itemId":"grep","type":"tool_call","kind":"search","title":"Search for NSSplitViewController","status":"completed"},
      {"itemId":"intro","type":"text","text":"I'll add an `NSOutlineView` source list:\\n\\n- **Pinned** above the projects\\n- projects ordered by their latest session\\n- a neutral grey selection"},
      {"itemId":"edit","type":"tool_call","kind":"edit","title":"Edit SidebarViewController.swift"\(permission)}\(reply)]}\(followUps)]
    """
  }
}
