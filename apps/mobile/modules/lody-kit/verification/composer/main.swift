import UIKit

func descendants(_ view: UIView) -> [UIView] {
  [view] + view.subviews.flatMap(descendants)
}

let composer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
composer.setInputIdentifier("create-session-input")
var height: CGFloat = 0
composer.onHeightChange = { height = $0 }
let ready = #"{"editable":true,"canSend":true,"sending":false,"notice":"","reconnect":false,"placeholder":"任务"}"#
composer.setComposerState(ready)
composer.layoutIfNeeded()
let input = descendants(composer).compactMap { $0 as? UITextView }.first!
let send = descendants(composer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-send" }!
// A standalone simulator executable has no UIApplication event loop. Invoke the
// real button's registered target action directly.
func tapSend() {
  for action in send.actions(forTarget: composer, forControlEvent: .touchUpInside) ?? [] {
    composer.perform(NSSelectorFromString(action))
  }
}
precondition(!send.isEnabled, "Empty draft must not send")
precondition(input.accessibilityIdentifier == "create-session-input")
composer.setInitialDraft("保留这个草稿 🐈")
var sent: [String] = []
composer.onSend = { sent.append($0["text"] as! String) }
tapSend()
tapSend()
precondition(sent == ["保留这个草稿 🐈"], "Double tap must send only once")
precondition(input.text.isEmpty && !send.isEnabled, "Pending draft must clear visibly and lock send")
composer.setComposerState(ready)
composer.restoreDraft(token: 1)
precondition(input.text == sent[0] && send.isEnabled, "Rejected creation must restore the exact draft")
tapSend()
composer.clearDraft(token: 1)
precondition(input.text.isEmpty && !send.isEnabled, "Accepted draft must stay cleared")
input.text = String(repeating: "多行输入\n", count: 50)
composer.textViewDidChange(input)
precondition(input.isScrollEnabled && height == 156, "Long drafts must stop growing and scroll")
composer.setComposerState(#"{"editable":false,"canSend":true,"sending":false,"notice":"结果待确认","reconnect":false,"placeholder":"任务"}"#)
precondition(!input.isEditable && !send.isEnabled, "Uncertain creation must prevent retry")
print("Composer: empty input, double send, restore, accept, multiline and uncertain state passed")

let attachmentComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 106))
attachmentComposer.setComposerState(ready)
attachmentComposer.setInitialAttachments(#"[{"id":"synthetic-file","name":"test.txt","uri":"file:///tmp/lody-composer-test.txt","kind":"file"}]"#)
let attachButton = descendants(attachmentComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-attach" }!
precondition(attachButton.isEnabled && attachButton.menu?.children.count == 3, "Plus must offer the existing photo and file pickers")
let attachmentSend = descendants(attachmentComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-send" }!
precondition(attachmentSend.isEnabled, "Attachment-only drafts must be sendable")
var sentAttachments: [[String: String]] = []
attachmentComposer.onSend = { sentAttachments = $0["attachments"] as! [[String: String]] }
func sendAttachment() {
  for action in attachmentSend.actions(forTarget: attachmentComposer, forControlEvent: .touchUpInside) ?? [] {
    attachmentComposer.perform(NSSelectorFromString(action))
  }
}
sendAttachment()
precondition(sentAttachments.first?["id"] == "synthetic-file", "First turn must carry the picked file")
attachmentComposer.restoreDraft(token: 1)
precondition(attachmentSend.isEnabled, "Upload failure must restore attachment-only draft")
sentAttachments = []
sendAttachment()
precondition(sentAttachments.first?["uri"] == "file:///tmp/lody-composer-test.txt", "Retry must preserve the original attachment URI")
print("Composer: plus menu and attachment-only send/restore/retry passed")

let draftComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
draftComposer.setComposerState(ready)
let draftInput = descendants(draftComposer).compactMap { $0 as? UITextView }.first!
var savedDrafts: [String] = []
draftComposer.onDraftChange = { savedDrafts.append($0) }
draftComposer.setStoredDraft("上次没发出去的话")
precondition(draftInput.text == "上次没发出去的话", "Empty input must restore the stored draft")
draftComposer.setStoredDraft("其他会话的草稿")
precondition(draftInput.text == "上次没发出去的话", "A stored draft must never overwrite typed text")
draftComposer.textViewDidEndEditing(draftInput)
precondition(savedDrafts == ["上次没发出去的话"], "Ending editing must persist the draft")
draftComposer.setComposerState(#"{"editable":true,"canSend":true,"sending":true,"notice":"","reconnect":false,"placeholder":"任务"}"#)
draftComposer.clearDraft(token: 1)
precondition(savedDrafts.last == "" && draftInput.text.isEmpty, "Sending must clear the stored draft")
print("Composer: stored draft restore, no-overwrite, save on end editing and clear on send passed")

let handoffComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
handoffComposer.setComposerState(ready)
let handoffInput = descendants(handoffComposer).compactMap { $0 as? UITextView }.first!
let handoffSend = descendants(handoffComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-send" }!
let transferred = try! JSONDecoder().decode(ChatPendingSend.self, from: Data(#"{"id":"handoff","text":"移交的草稿","attachments":[],"status":"正在发送…"}"#.utf8))
handoffComposer.setPendingSend(transferred)
precondition(handoffInput.text.isEmpty && !handoffSend.isEnabled, "A transferred send locks the destination composer without exposing the draft")
var rejected = transferred
rejected.failed = true
handoffComposer.setPendingSend(rejected)
precondition(handoffInput.text == "移交的草稿", "Failure restores a draft across native hosts")
handoffInput.text = "用户继续修改"
handoffComposer.setPendingSend(rejected)
precondition(handoffInput.text == "用户继续修改", "Repeated failed props must not replace user edits")
var generatedID = ""
handoffComposer.onSend = { generatedID = $0["id"] as! String }
handoffComposer.textViewDidChange(handoffInput)
for action in handoffSend.actions(forTarget: handoffComposer, forControlEvent: .touchUpInside) ?? [] {
  handoffComposer.perform(NSSelectorFromString(action))
}
precondition(UUID(uuidString: generatedID) != nil, "The native click must generate a dispatch identity before emitting send")
print("Composer handoff: destination ownership, failed restore, no-overwrite and send identity passed")

handoffComposer.clearDraft(token: 1)
handoffInput.text = "下一条草稿"
handoffComposer.clearDraft(token: 2)
precondition(handoffInput.text == "下一条草稿", "A delayed acknowledgement cannot erase a new draft")

let acknowledged = try! JSONDecoder().decode(ChatPendingSend.self, from: Data(#"{"id":"acknowledged","text":"已送达","attachments":[],"status":"等待回复…"}"#.utf8))
handoffComposer.setPendingSend(acknowledged)
handoffComposer.clearDraft(token: 3)
handoffComposer.setPendingSend(acknowledged)
handoffInput.text = "下一条"
handoffComposer.textViewDidChange(handoffInput)
precondition(handoffSend.isEnabled, "A status update for an acknowledged ID must never reacquire the draft lock")

let typingComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
typingComposer.setComposerState(ready)
let typingInput = descendants(typingComposer).compactMap { $0 as? UITextView }.first!
let typingSend = descendants(typingComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-send" }!
typingComposer.setPendingSend(transferred)
precondition(typingInput.isEditable && !typingSend.isEnabled, "Pending sends must keep input editable while preventing duplicate submission")
typingInput.text = "下一条新草稿"
typingComposer.textViewDidChange(typingInput)
typingComposer.setPendingSend(rejected)
precondition(typingInput.text == "下一条新草稿" && !typingSend.isEnabled, "Failed sending must preserve the next draft and require merging before another send")
let merge = descendants(typingComposer).compactMap { $0 as? UIButton }.first { $0.title(for: .normal)?.contains("合并到草稿") == true }!
for action in merge.actions(forTarget: typingComposer, forControlEvent: .touchUpInside) ?? [] {
  typingComposer.perform(NSSelectorFromString(action))
}
precondition(typingInput.text == "下一条新草稿\n\n移交的草稿" && typingSend.isEnabled, "Explicit merging must retain both drafts and unlock sending")
print("Composer continuity: editable pending input and lossless failed-draft merge passed")
for action in typingSend.actions(forTarget: typingComposer, forControlEvent: .touchUpInside) ?? [] {
  typingComposer.perform(NSSelectorFromString(action))
}
typingInput.text = "第三条草稿"
typingComposer.textViewDidChange(typingInput)
typingComposer.clearDraft(token: 1)
precondition(typingInput.text == "第三条草稿" && typingSend.isEnabled, "Acknowledgement must release the sent draft while retaining text typed during delivery")

for storedFirst in [true, false] {
  let restoredComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
  restoredComposer.setComposerState(ready)
  let restoredInput = descendants(restoredComposer).compactMap { $0 as? UITextView }.first!
  if storedFirst { restoredComposer.setStoredDraft("重开后继续写的下一条") }
  restoredComposer.setPendingSend(transferred)
  if !storedFirst { restoredComposer.setStoredDraft("重开后继续写的下一条") }
  precondition(restoredInput.text == "重开后继续写的下一条", "Pending and next-draft hydration must preserve text in either order")
}
var persistedTyping: [String] = []
typingComposer.onDraftChange = { persistedTyping.append($0) }
for action in typingSend.actions(forTarget: typingComposer, forControlEvent: .touchUpInside) ?? [] {
  typingComposer.perform(NSSelectorFromString(action))
}
precondition(persistedTyping.last == "", "Sending must immediately clear the current draft store while the outbox retains the sent content")
typingComposer.textViewDidEndEditing(typingInput)
precondition(persistedTyping.last == "", "An empty current input must never persist the pending message as a new draft")
print("Composer persistence: either hydration order and current-only draft writes passed")
