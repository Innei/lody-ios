import UIKit

func descendants(_ view: UIView) -> [UIView] {
  [view] + view.subviews.flatMap(descendants)
}

let composer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
composer.setInputIdentifier("create-session-input")
var height: CGFloat = 0
composer.onHeightChange = { height = $0 }
let ready = #"{"editable":true,"canSend":true,"sending":false,"notice":"","reconnect":false,"placeholder":"任务"}"#

func verifyCollapsedTypography(_ category: UIContentSizeCategory, expectedPointSize: CGFloat) {
  var scaledComposer: ChatComposerView!
  UITraitCollection(preferredContentSizeCategory: category).performAsCurrent {
    scaledComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
  }
  scaledComposer.setComposerState(ready)
  scaledComposer.layoutIfNeeded()
  let scaledInput = descendants(scaledComposer).compactMap { $0 as? UITextView }.first!
  let placeholder = descendants(scaledComposer).compactMap { $0 as? UILabel }.first { $0.text == "任务" }!
  precondition(abs(scaledInput.font!.pointSize - expectedPointSize) < 0.1, "Composer font must respect the app-supported scale limit")
  precondition(abs(scaledInput.bounds.height - 48) < 0.5, "An empty collapsed composer must remain one 48-point row")
  let inputLineMidY = scaledInput.textContainerInset.top + scaledInput.font!.lineHeight / 2
  precondition(abs(inputLineMidY - scaledInput.bounds.midY) < 0.5, "Collapsed input text must be vertically centered")
  precondition(abs(placeholder.frame.midY - scaledInput.frame.midY) < 0.5, "Collapsed placeholder must be vertically centered")
}

verifyCollapsedTypography(.extraSmall, expectedPointSize: 14)
verifyCollapsedTypography(.accessibilityExtraExtraExtraLarge, expectedPointSize: 23)
print("Composer typography: supported minimum and maximum sizes stay centered in one row")

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

let actionComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
let actionWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
actionWindow.addSubview(actionComposer)
actionWindow.isHidden = false
actionComposer.setComposerState(ready)
actionComposer.layoutIfNeeded()
let actionInput = descendants(actionComposer).compactMap { $0 as? UITextView }.first!
actionInput.text = "Send this"
actionComposer.textViewDidChange(actionInput)
let actionButton = descendants(actionComposer).compactMap { $0 as? UIButton }.first {
  $0.accessibilityIdentifier == "session-send"
}!
let actionVisual = descendants(actionButton).first { $0.accessibilityIdentifier == "session-action-visual" }
precondition(
  actionVisual?.backgroundColor?.isEqual(UIColor.systemBlue) == true,
  "An actionable Send must render as a blue circular control"
)
actionInput.text = ""
actionComposer.textViewDidChange(actionInput)
actionComposer.setComposerState(
  #"{"editable":true,"canSend":true,"sending":false,"running":true,"canStop":true,"notice":"","reconnect":false,"placeholder":"任务"}"#
)
precondition(
  actionVisual?.backgroundColor?.isEqual(UIColor.systemRed) == true,
  "Stop must render as a red circular control"
)
actionComposer.setComposerState(
  #"{"editable":true,"canSend":true,"sending":false,"running":true,"canStop":true,"stopping":true,"notice":"","reconnect":false,"placeholder":"任务"}"#
)
precondition(
  actionVisual?.isHidden == false
    && actionVisual?.backgroundColor?.isEqual(UIColor.systemGray) == true,
  "Loading must keep the circular control visible and turn it gray"
)
let actionProgress = descendants(actionButton).first {
  $0.accessibilityIdentifier == "session-action-progress"
}
precondition(
  actionProgress?.isHidden == false
    && actionProgress?.layer.animation(forKey: "composer.loading.rotation") != nil,
  "Loading must replace the action symbol with a rotating white arc"
)
precondition(
  !descendants(actionButton).compactMap { $0 as? UIActivityIndicatorView }.contains { $0.isAnimating },
  "Loading must not fall back to the detached activity indicator"
)
actionInput.text = "Next"
actionComposer.textViewDidChange(actionInput)
actionComposer.setComposerState(ready)
let actionContent = descendants(actionButton).first {
  $0.accessibilityIdentifier == "session-action-content"
}
precondition(
  actionContent?.layer.animationKeys()?.isEmpty == false,
  "Action-state replacement must animate the icon content"
)
print("Composer action: Send is blue, Stop is red and Loading is a gray circle with a rotating arc")

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

let pasteComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
pasteComposer.setComposerState(ready)
let pasteInput = descendants(pasteComposer).compactMap { $0 as? UITextView }.first!
let pasteSend = descendants(pasteComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-send" }!
let source = FileManager.default.temporaryDirectory.appendingPathComponent("lody-paste-source.txt")
try! Data("clipboard file".utf8).write(to: source)
let fileProvider = NSItemProvider(contentsOf: source)!
precondition(pasteInput.canPaste([fileProvider]), "A copied file must enable the system Paste action")
UIPasteboard.general.setObjects([source as NSURL])
precondition(pasteInput.canPerformAction(#selector(UIResponderStandardEditActions.paste(_:)), withSender: nil), "A copied file must expose Paste in the edit menu")
pasteInput.paste(itemProviders: [fileProvider])
let deadline = Date().addingTimeInterval(3)
while !pasteSend.isEnabled && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
precondition(pasteSend.isEnabled, "Pasting a file must add a sendable attachment")
var pastedAttachments: [[String: String]] = []
pasteComposer.onSend = { pastedAttachments = $0["attachments"] as! [[String: String]] }
for action in pasteSend.actions(forTarget: pasteComposer, forControlEvent: .touchUpInside) ?? [] {
  pasteComposer.perform(NSSelectorFromString(action))
}
precondition(pastedAttachments.first?["name"] == source.lastPathComponent, "A pasted file must retain its name")
let pastedURL = URL(string: pastedAttachments.first!["uri"]!)!
precondition(pastedURL != source && (try? Data(contentsOf: pastedURL)) == Data("clipboard file".utf8), "A pasted file must be copied before the provider expires")
let textProvider = NSItemProvider(object: "normal text paste" as NSString)
pasteComposer.restoreDraft(token: 1)
pasteInput.text = ""
pasteInput.paste(itemProviders: [textProvider])
let textDeadline = Date().addingTimeInterval(3)
while pasteInput.text.isEmpty && Date() < textDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
precondition(pasteInput.text == "normal text paste", "Ordinary text paste must keep UIKit behavior")
UIPasteboard.general.items = []
print("Composer paste: file attachment and ordinary text fallback passed")

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
var generatedStartedAt: Double = 0
let beforeNativeSend = Date().timeIntervalSince1970 * 1000
handoffComposer.onSend = {
  generatedID = $0["id"] as! String
  generatedStartedAt = $0["startedAt"] as? Double ?? 0
}
handoffComposer.textViewDidChange(handoffInput)
for action in handoffSend.actions(forTarget: handoffComposer, forControlEvent: .touchUpInside) ?? [] {
  handoffComposer.perform(NSSelectorFromString(action))
}
let afterNativeSend = Date().timeIntervalSince1970 * 1000
precondition(UUID(uuidString: generatedID) != nil, "The native click must generate a dispatch identity before emitting send")
precondition((beforeNativeSend...afterNativeSend).contains(generatedStartedAt),
  "The native send event must carry the timer's durable submission clock")
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
let merge = descendants(typingComposer).compactMap { $0 as? UIButton }.first { $0.title(for: .normal)?.contains("native.chat.composer.failedDraft") == true }!
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

// A cancelled throw must reveal its destination and never adopt stale content.
let throwWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
let throwInput = UITextView(frame: CGRect(x: 16, y: 700, width: 350, height: 60))
throwInput.text = "Preserve this message"
throwWindow.addSubview(throwInput)
let throwTarget = ChatMessageContent(frame: CGRect(x: 200, y: 100, width: 170, height: 45))
throwTarget.label.setText(NSAttributedString(string: throwInput.text))
throwWindow.addSubview(throwTarget)
ChatSendHandoff.begin(id: "cancel-throw", text: throwInput.text, source: throwInput)
ChatSendHandoff.hold(id: "cancel-throw", target: throwTarget)
precondition(throwTarget.isHidden, "The destination must not duplicate the flying message")
ChatSendHandoff.deliver(id: "cancel-throw", to: throwTarget)
let flyingText = throwWindow.subviews.compactMap { $0 as? ChatMessageContent }.first { $0 !== throwTarget }
precondition(flyingText != nil && flyingText!.label.bounds.width > 0 && flyingText!.label.bounds.height > 0,
  "The hidden background layer must not skip the flying text layout")
ChatSendHandoff.cancel(id: "cancel-throw")
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
precondition(!throwTarget.isHidden, "Cancellation must reveal the destination")
precondition(throwWindow.subviews.count == 2, "Cancellation must remove every flight overlay")
print("Send throw: cancellation reveals target, removes overlays without replacing destination content")

let queueComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 244))
let runningState = #"{"editable":true,"canSend":true,"sending":false,"running":true,"canStop":true,"notice":"","reconnect":false,"placeholder":"任务"}"#
queueComposer.setComposerState(runningState)
let queueInput = descendants(queueComposer).compactMap { $0 as? UITextView }.first!
let queueSend = descendants(queueComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-stop" }!
var stopCalls = 0
var queuePayload: [String: Any] = [:]
queueComposer.onStop = { stopCalls += 1 }
queueComposer.onSend = { queuePayload = $0 }
func tapQueueAction() {
  for action in queueSend.actions(forTarget: queueComposer, forControlEvent: .touchUpInside) ?? [] {
    queueComposer.perform(NSSelectorFromString(action))
  }
}
tapQueueAction()
precondition(stopCalls == 1 && queuePayload.isEmpty, "Empty running input must stop without creating a message")
queueInput.text = "  "
queueComposer.textViewDidChange(queueInput)
precondition(queueSend.accessibilityIdentifier == "session-stop", "Whitespace is not a draft")
queueInput.text = "Next instruction"
queueComposer.textViewDidChange(queueInput)
precondition(queueSend.accessibilityIdentifier == "session-send" && queueSend.isEnabled, "Typing switches Stop to Send")
tapQueueAction()
precondition(queuePayload["queue"] as? Bool == true && queueInput.text.isEmpty, "Busy submission must queue and clear the draft")
queueComposer.clearDraft(token: 1)
precondition(queueSend.accessibilityIdentifier == "session-stop" && queueSend.isEnabled, "Queue ACK restores Stop")
queueComposer.setQueue((1...4).map { ChatQueuedDraft(id: "q\($0)", text: "Queued \($0)") })
queueComposer.layoutIfNeeded()
let queuePanel = descendants(queueComposer).first { $0.accessibilityIdentifier == "session-queue" }!
precondition(queuePanel.bounds.height == 132 && !queuePanel.isHidden, "Long plain queues stay compact at three 44 pt rows and scroll")
queueComposer.setQueue([
  ChatQueuedDraft(id: "q1", text: "Queued 1"),
  ChatQueuedDraft(id: "q2", text: "Queued 2", attachments: ["shot.png"]),
])
queueComposer.layoutIfNeeded()
let queuedRows = descendants(queuePanel).compactMap { $0 as? UILabel }
precondition(queuedRows.contains { $0.text == "shot.png" }, "Queued attachments must show their file names")
precondition(queuePanel.bounds.height > 44 + 44, "An attachment row is taller than a plain row")
queueComposer.setQueue([ChatQueuedDraft(id: "q3", text: "", attachments: ["shot.png"])])
queueComposer.layoutIfNeeded()
precondition(
  descendants(queuePanel).compactMap { ($0 as? UILabel)?.text }.contains(LodyStrings.text("native.chat.row.queuedAttachmentsOnly")),
  "An attachment-only queued turn needs a message placeholder"
)
queueComposer.setQueue([])
precondition(queuePanel.isHidden, "Drained queue must leave no empty card")
queueComposer.setInitialAttachments(#"[{"id":"queue-file","name":"next.txt","uri":"file:///tmp/next.txt","kind":"file"}]"#)
precondition(queueSend.accessibilityIdentifier == "session-send" && queueSend.isEnabled, "An attachment switches Stop to Send even with empty text")
print("Queue composer: Stop, whitespace, typing, queued submission, ACK, bounded queue and attachment-only input passed")

// A steered queue row hands its frame to the send animation instead of vanishing.
let steerWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
let steerComposer = ChatComposerView(frame: CGRect(x: 0, y: 600, width: 390, height: 244))
steerWindow.addSubview(steerComposer)
steerWindow.isHidden = false
steerComposer.setComposerState(runningState)
steerComposer.setQueue([ChatQueuedDraft(id: "s1", text: "Steer me"), ChatQueuedDraft(id: "s2", text: "Stay queued")])
steerComposer.layoutIfNeeded()
steerComposer.setQueue([ChatQueuedDraft(id: "s2", text: "Stay queued")])
precondition(ChatSendHandoff.isWaiting(id: "s1"), "A steered row must start its flight before leaving the queue")
precondition(!ChatSendHandoff.isWaiting(id: "s2"), "A row that stays queued must not fly")
let steerTarget = ChatMessageContent(frame: CGRect(x: 200, y: 120, width: 170, height: 45))
steerTarget.label.setText(NSAttributedString(string: "Steer me"))
steerWindow.addSubview(steerTarget)
ChatSendHandoff.hold(id: "s1", target: steerTarget)
ChatSendHandoff.deliver(id: "s1", to: steerTarget)
let steerFlight = steerWindow.subviews.compactMap { $0 as? ChatMessageContent }.first { $0 !== steerTarget }
precondition(steerFlight?.layer.animation(forKey: "throw.scale") == nil, "A steered message slides straight, without the throw squash")
precondition(steerFlight?.layer.animation(forKey: "throw.position") != nil, "A steered message must animate to its landed row")
ChatSendHandoff.cancel(id: "s1")
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
precondition(!steerTarget.isHidden, "Cancelling a steer flight must reveal the landed row")
print("Steer flight: departing queue rows slide straight into the transcript and clean up on cancellation")


let modelComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 120))
modelComposer.setComposerState(ready)
modelComposer.setComposerOptions(#"{"modelId":"gpt","models":[{"id":"gpt","title":"GPT"}],"effort":"medium","efforts":[{"id":"medium","title":"Medium"}]}"#)
let modelButton = descendants(modelComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-model" }!
precondition(
  modelButton.configuration?.preferredSymbolConfigurationForImage
    == UIImage.SymbolConfiguration(pointSize: 5, weight: .medium),
  "The model trigger chevron must use the compact 5-point symbol size"
)
print("Composer: model trigger chevron stays compact")

if #available(iOS 26.0, *) {
  let glassComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
  let glassWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
  glassWindow.addSubview(glassComposer)
  glassWindow.isHidden = false
  glassComposer.onHeightChange = { height in
    glassComposer.frame.size.height = height
  }
  glassComposer.setComposerState(ready)
  glassComposer.setComposerOptions(
    #"{"modelId":"gpt","models":[{"id":"gpt","title":"GPT"}],"effort":"medium","efforts":[{"id":"medium","title":"Medium"}]}"#
  )
  glassComposer.layoutIfNeeded()

  let glassInput = descendants(glassComposer).compactMap { $0 as? UITextView }.first!
  let glassAttach = descendants(glassComposer).compactMap { $0 as? UIButton }.first {
    $0.accessibilityIdentifier == "session-attach"
  }!
  let glassSend = descendants(glassComposer).compactMap { $0 as? UIButton }.first {
    $0.accessibilityIdentifier == "session-send"
  }!
  let glassModel = descendants(glassComposer).compactMap { $0 as? UIButton }.first {
    $0.accessibilityIdentifier == "session-model"
  }!
  let glassInputSurface = glassInput.superview!.superview as! UIVisualEffectView
  let glassAttachSurface = glassAttach.superview!.superview as! UIVisualEffectView

  precondition(
    abs(glassInputSurface.frame.minX - glassAttachSurface.frame.maxX - 8) < 0.5,
    "An unfocused iOS 26 composer must keep the current separate 8-point glass gap"
  )
  let glassAttachGlyph = descendants(glassAttach).compactMap { $0 as? UIImageView }.first {
    $0.accessibilityIdentifier == "session-attach-glyph"
  }
  precondition(
    glassAttachGlyph != nil && glassAttach.image(for: .normal) == nil,
    "Liquid Glass must own a stable Add glyph view so UIButton relayout cannot reset its scale"
  )
  let restingAttachGlyphSize = glassAttachGlyph!.bounds.size
  precondition(glassInput.becomeFirstResponder(), "The glass composer input must accept focus")
  RunLoop.current.run(until: Date().addingTimeInterval(0.05))
  glassComposer.layoutIfNeeded()

  let focusedInputFrame = glassInputSurface.convert(glassInputSurface.bounds, to: glassComposer)
  let focusedAttachFrame = glassAttachSurface.convert(glassAttachSurface.bounds, to: glassComposer)
  precondition(
    abs(focusedInputFrame.minX + 2 - focusedAttachFrame.minX) < 0.5
      && focusedInputFrame.contains(focusedAttachFrame),
    "A focused iOS 26 composer must merge the optically inset add glass into one full-width input surface"
  )

  let attachCenter = glassAttach.convert(
    CGPoint(x: glassAttach.bounds.midX, y: glassAttach.bounds.midY),
    to: glassInputSurface
  )
  let sendCenter = glassSend.convert(
    CGPoint(x: glassSend.bounds.midX, y: glassSend.bounds.midY),
    to: glassInputSurface
  )
  let modelFrame = glassModel.convert(glassModel.bounds, to: glassInputSurface)
  let sendFrame = glassSend.convert(glassSend.bounds, to: glassInputSurface)
  let attachInset = attachCenter.x
  let sendInset = glassInputSurface.bounds.maxX - sendCenter.x
  let baselineDelta = attachCenter.y - sendCenter.y
  print(
    "Composer glass metrics: add \(attachInset), send \(sendInset), baseline \(baselineDelta)"
  )
  precondition(
    abs(attachInset - 24) < 0.5
      && abs(sendInset - 24) < 0.5
      && abs(baselineDelta) < 0.5,
    "Focused add and send controls must balance on one baseline with mirrored 24-point centers; "
      + "got add \(attachInset), send \(sendInset), baseline \(baselineDelta)"
  )
  let sendVisualView = descendants(glassSend).first {
    $0.accessibilityIdentifier == "session-action-visual"
  }!
  let sendGlyph = descendants(sendVisualView).compactMap { $0 as? UIImageView }.first {
    !$0.isHidden && $0.image != nil
  }!
  let expectedFocusedScale: CGFloat = 11 / 17
  let focusedAttachGlyphSize = glassAttachGlyph!.bounds.size
  precondition(
    abs(focusedAttachGlyphSize.width / restingAttachGlyphSize.width - expectedFocusedScale) < 0.02
      && abs(focusedAttachGlyphSize.height / restingAttachGlyphSize.height - expectedFocusedScale) < 0.02,
    "The focused Add glyph must shrink from 17 points to the optically balanced 11-point size; "
      + "got \(restingAttachGlyphSize) -> \(focusedAttachGlyphSize)"
  )
  let attachGlyphCenter = glassAttachGlyph!.convert(
    CGPoint(x: glassAttachGlyph!.bounds.midX, y: glassAttachGlyph!.bounds.midY),
    to: glassInputSurface
  )
  let sendGlyphCenter = sendGlyph.convert(
    CGPoint(x: sendGlyph.bounds.midX, y: sendGlyph.bounds.midY),
    to: glassInputSurface
  )
  precondition(
    abs(attachGlyphCenter.y - sendGlyphCenter.y) < 0.5,
    "The focused Add and Send icons must share one baseline; "
      + "got \(attachGlyphCenter.y) and \(sendGlyphCenter.y)"
  )
  precondition(
    !glassModel.isHidden
      && modelFrame.midX > glassInputSurface.bounds.midX
      && modelFrame.maxX <= sendFrame.minX + 0.5,
    "The focused model selector must remain on the trailing side before Send"
  )
  print("Composer glass: focus merges Add into one balanced surface while Model stays trailing")
}
