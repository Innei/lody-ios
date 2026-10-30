#if DEBUG
import Foundation
import LodyData

@MainActor
final class MacTranscriptFixture {
  private var answered: String?
  private var replies: [String] = []
  private var changed: (@MainActor (SessionFeedState) -> Void)?
  private let earlier: String
  private let media: Bool

  init(history: Int = 0, media: Bool = false) {
    self.media = media
    earlier = (0..<history).map { index in
      let role = index.isMultiple(of: 2) ? "user" : "assistant"
      return #"{"id":"h\#(index)","role":"\#(role)","status":"completed","finished":true,"items":[{"itemId":"t","type":"text","text":"Earlier turn \#(index)"}]},"#
    }.joined()
  }

  var source: MacTranscriptSource {
    MacTranscriptSource(
      start: { [self] changed in
        self.changed = changed
        changed(state)
      },
      stop: { [self] in changed = nil },
      detail: { _ in nil },
      respond: { [self] _, optionId in
        answered = optionId
        changed?(state)
        return .accepted
      },
      media: MacFixtureMedia()
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

  private var userMedia: String {
    guard media else { return "" }
    return #"{"itemId":"f","type":"file","file":{"id":"file-spec","fileName":"sidebar-spec.pdf","sizeBytes":48213}},{"itemId":"p","type":"image","image":{"id":"img-mock","fileName":"mock.png","width":1200,"height":800}},"#
  }

  private var replyMedia: String {
    guard media else { return "" }
    return #"{"itemId":"shot","type":"image","image":{"id":"img-layout","fileName":"layout.png","width":1600,"height":1000}},"#
  }

  private var json: String {
    let permission = answered == nil
      ? #","permission":{"pending":true,"requestId":"r-edit","options":[{"optionId":"allow","name":"Allow","kind":"allow_once"},{"optionId":"deny","name":"Deny","kind":"reject_once"}]}"#
      : #","status":"completed""#
    let reply = answered == nil ? "" : #",{"itemId":"done","type":"text","text":"Approved. The sidebar now groups sessions by project, with **Pinned** on top."}"#
    return """
    [\(earlier){"id":"u1","role":"user","status":"completed","finished":true,"items":[\(userMedia){"itemId":"q","type":"text","text":"Add a sidebar like the Codex desktop app: pinned sessions, then projects."}]},
     {"id":"a1","role":"assistant","status":"completed","finished":true,"items":[
      {"itemId":"think","type":"thought","text":"Reading the window shell first"},
      {"itemId":"read","type":"tool_call","kind":"read","title":"Read MainWindowController.swift","status":"completed"},
      {"itemId":"grep","type":"tool_call","kind":"search","title":"Search for NSSplitViewController","status":"completed"},\(replyMedia)
      {"itemId":"intro","type":"text","text":"I'll add an `NSOutlineView` source list:\\n\\n- **Pinned** above the projects\\n- projects ordered by their latest session\\n- a neutral grey selection"},
      {"itemId":"edit","type":"tool_call","kind":"edit","title":"Edit SidebarViewController.swift"\(permission)}\(reply)]}\(followUps)]
    """
  }
}
#endif
