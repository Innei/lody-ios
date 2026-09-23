import ChatKit
import AVFoundation
import UIKit
import UniformTypeIdentifiers

@MainActor func descendants(_ view: UIView) -> [UIView] {
  [view] + view.subviews.flatMap(descendants)
}

@MainActor func allWindows() -> [UIWindow] {
  var windows = UIApplication.shared.connectedScenes
    .compactMap { $0 as? UIWindowScene }
    .flatMap(\.windows)
  if let overlay = LodyToastOverlay.shared.hostedWindow, !windows.contains(where: { $0 === overlay }) {
    windows.append(overlay)
  }
  return windows
}

@MainActor func onMain<T>(_ body: @MainActor () -> T) -> T {
  body()
}

// Camera results use the same temporary-file/preview path as other attachments.
let capture = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 48)).image { context in
  UIColor.systemBlue.setFill()
  context.fill(CGRect(x: 0, y: 0, width: 32, height: 48))
}
let capturedPhoto = ChatCameraCapture.store(capture.jpegData(compressionQuality: 0.9)!)!
precondition(capturedPhoto.isImage && capturedPhoto.url.isFileURL)
precondition(ChatAttachment.thumbnail(capturedPhoto.url) != nil, "Captured photo must persist as a previewable attachment")
try FileManager.default.removeItem(at: capturedPhoto.url)
precondition(ChatCameraCapture.store(Data("invalid image".utf8)) == nil, "Invalid capture must not become an attachment")
print("Camera: valid JPEG storage and invalid image rejection pass")

// During the tile morph, the live layer keeps its crop and scales uniformly.
let cameraMorph = ChatAttachmentCameraView(session: AVCaptureSession())
let viewport = CGSize(width: 390, height: 430)
cameraMorph.frame = CGRect(x: 0, y: 0, width: 116, height: 116)
cameraMorph.prepareTransition(viewport: viewport)
for size in [CGSize(width: 116, height: 116), CGSize(width: 240, height: 280), viewport] {
  cameraMorph.frame.size = size
  cameraMorph.setNeedsLayout()
  cameraMorph.layoutIfNeeded()
  let live = cameraMorph.previewLayer
  precondition(live.bounds.size == viewport, "Live preview must not recrop independently during the morph")
  let transform = live.affineTransform()
  precondition(abs(transform.a - transform.d) < 0.001, "Camera contents must never stretch")
  precondition(live.frame.width >= size.width - 0.01 && live.frame.height >= size.height - 0.01,
    "Preview must cover the moving viewport without exposing blank edges")
}
cameraMorph.prepareTransition(viewport: nil)
let fullCamera = ChatAttachmentSheet(cameraOnly: true)
fullCamera.loadViewIfNeeded()
precondition(fullCamera.modalPresentationStyle == .fullScreen)
precondition(!descendants(fullCamera.view).contains { $0 is UICollectionView },
  "Direct capture must not construct a recent-photo grid underneath")
cameraMorph.letterboxed = true
cameraMorph.setExpanded(true)
cameraMorph.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
cameraMorph.controlInsets = UIEdgeInsets(top: 62, left: 0, bottom: 34, right: 0)
cameraMorph.setNeedsLayout()
cameraMorph.layoutIfNeeded()
let finder = cameraMorph.previewLayer.frame
precondition(abs(finder.width / finder.height - 0.75) < 0.001)
let cameraButtons = descendants(cameraMorph)
let closeFrame = cameraButtons.first { $0.accessibilityIdentifier == "camera-collapse" }!.frame
let shutterFrame = cameraButtons.first { $0.accessibilityIdentifier == "camera-shutter" }!.frame
precondition(closeFrame.maxY <= finder.minY && shutterFrame.minY >= finder.maxY,
  "Full-screen controls must stay in the black bars outside the 3:4 viewfinder")
print("Camera: uniform preview morph, independent full-screen entry and 3:4 viewfinder pass")

let composer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
let initialScroll = UIScrollView()
initialScroll.bottomEdgeEffect.isHidden = true
composer.attachScrollEdge(to: initialScroll)
let scrollInteraction = composer.interactions.compactMap { $0 as? UIScrollEdgeElementContainerInteraction }.first!
precondition(scrollInteraction.scrollView === initialScroll && scrollInteraction.edge == .bottom)
precondition(!initialScroll.bottomEdgeEffect.isHidden && initialScroll.bottomEdgeEffect.style == .soft,
  "Attaching a composer must enable soft occlusion without RNSScreen discovery")
let chatScroll = UIScrollView()
composer.attachScrollEdge(to: chatScroll, style: .automatic)
precondition(scrollInteraction.scrollView === chatScroll && chatScroll.bottomEdgeEffect.style == .automatic,
  "Chat must keep automatic occlusion when the composer attaches")
let replacementScroll = UIScrollView()
composer.attachScrollEdge(to: replacementScroll)
precondition(scrollInteraction.scrollView === replacementScroll && replacementScroll.bottomEdgeEffect.style == .soft,
  "Moving the composer to another host must configure the new scroll view")
composer.attachScrollEdge(to: nil)
precondition(scrollInteraction.scrollView == nil,
  "Detaching the composer must release its scroll target")
print("Composer scroll edge: direct attachment, host replacement and detachment pass")
let photoSheet = ChatAttachmentSheet()
photoSheet.loadViewIfNeeded()
photoSheet.view.frame = CGRect(x: 0, y: 0, width: 390, height: 430)
photoSheet.additionalSafeAreaInsets.bottom = 34
photoSheet.view.layoutIfNeeded()
let photoScroll = photoSheet.contentScrollView(for: .bottom)
precondition(photoScroll?.frame == photoSheet.view.bounds, "Photo grid must reach the sheet edges despite bottom safe area")
precondition(photoScroll is UICollectionView && photoSheet.contentScrollView(for: .top) === photoScroll,
  "Photo selection must publish its native grid as the sheet's scroll content")
let photoEdges = descendants(photoSheet.view).flatMap(\.interactions)
  .compactMap { $0 as? UIScrollEdgeElementContainerInteraction }
precondition(photoEdges.count == 1 && photoEdges[0].scrollView == nil,
  "The confirmation overlay must not occlude photos before a selection exists")
composer.setInputIdentifier("create-session-input")
var height: CGFloat = 0
composer.onHeightChange = { height = $0 }
let ready = #"{"editable":true,"canSend":true,"sending":false,"notice":"","reconnect":false,"placeholder":"任务"}"#

@MainActor func verifyCollapsedTypography(_ category: UIContentSizeCategory, expectedPointSize: CGFloat) {
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
@MainActor func tapSend() {
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
  actionVisual?.backgroundColor?.resolvedColor(with: actionComposer.traitCollection).isEqual(UIColor.lodyAccent.resolvedColor(with: actionComposer.traitCollection)) == true,
  "An actionable Send must render as an accent circular control"
)
let originalAccent = LodyAccentChoice.current.rawValue
LodyAccentChoice.save("purple")
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
for host in [composer, actionComposer] {
  let visual = descendants(host).first { $0.accessibilityIdentifier == "session-action-visual" }!
  precondition(visual.backgroundColor?.resolvedColor(with: host.traitCollection).isEqual(UIColor.systemPurple.resolvedColor(with: host.traitCollection)) == true,
    "Existing chat and sheet composers must recolor when the accent changes")
}
LodyAccentChoice.save("unknown")
precondition(LodyAccentChoice.current == .purple, "An unknown accent must not replace the saved choice")
for value in ["#FFFFAA", "#123abc"] {
  LodyAccentChoice.save(value)
  RunLoop.main.run(until: Date().addingTimeInterval(0.05))
  precondition(UserDefaults.standard.string(forKey: "accentColor") == value.uppercased())
  precondition(LodyAccentChoice.hex(LodyAccentChoice.current.rawValue, dark: false) == value.uppercased())
  precondition(LodyAccentChoice.hex(LodyAccentChoice.current.rawValue, dark: true) == value.uppercased())
  for host in [composer, actionComposer] {
    let visual = descendants(host).first { $0.accessibilityIdentifier == "session-action-visual" }!
    precondition(visual.backgroundColor?.isEqual(LodyAccentChoice.current.color) == true,
      "A custom accent must update existing chat and sheet send controls")
    let symbol = descendants(visual).compactMap { $0 as? UIImageView }.first!
    precondition(symbol.tintColor.isEqual(value == "#FFFFAA" ? UIColor.black : UIColor.white),
      "Bright custom colors need a readable send glyph")
  }
  for invalid in ["#123", "#GGFFFF", "#12345678", "#123456\n", "unknown"] { LodyAccentChoice.save(invalid) }
  precondition(LodyAccentChoice.current.rawValue == value.uppercased(), "Invalid values cannot overwrite a custom color")
}
LodyAccentChoice.save(originalAccent)
RunLoop.main.run(until: Date().addingTimeInterval(0.05))
print("Composer: persisted accent changes update existing hosts and reject unknown choices")

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
precondition(attachButton.isEnabled, "An attachment draft must still allow adding attachments")
let attachmentSend = descendants(attachmentComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-send" }!
precondition(attachmentSend.isEnabled, "Attachment-only drafts must be sendable")
var sentAttachments: [[String: String]] = []
attachmentComposer.onSend = { sentAttachments = $0["attachments"] as! [[String: String]] }
@MainActor func sendAttachment() {
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

let webArchiveType = UTType("com.apple.webarchive")!
let selection = NSItemProvider()
selection.registerDataRepresentation(forTypeIdentifier: webArchiveType.identifier, visibility: .all) { completion in
  completion(Data("webarchive-bytes".utf8), nil)
  return nil
}
selection.registerObject("lodyUserBubble" as NSString, visibility: .all)
precondition(ChatAttachment.transferType(for: selection) == nil,
  "A copied web selection must not become a file attachment")
precondition(!ChatAttachment.canPaste([selection]),
  "A copied web selection must not claim Paste as an attachment")
pasteComposer.restoreDraft(token: 1)
pasteInput.text = ""
pasteInput.paste(itemProviders: [selection])
let webDeadline = Date().addingTimeInterval(3)
while pasteInput.text != "lodyUserBubble" && Date() < webDeadline {
  RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
precondition(pasteInput.text == "lodyUserBubble", "Copied in-app text must paste as text, not a webarchive file")

let archiveFile = FileManager.default.temporaryDirectory.appendingPathComponent("selection.webarchive")
try! Data("webarchive-bytes".utf8).write(to: archiveFile)
let archiveFileProvider = NSItemProvider(contentsOf: archiveFile)!
archiveFileProvider.suggestedName = archiveFile.lastPathComponent
let archiveText = NSItemProvider(object: "lodyUserBubble" as NSString)
precondition(ChatAttachment.transferType(for: archiveFileProvider) == nil,
  "A webarchive file URL must not become an attachment")
precondition(!ChatAttachment.canPaste([archiveFileProvider, archiveText]),
  "A split webarchive + text paste must not claim the paste as an attachment")
pasteComposer.restoreDraft(token: 1)
pasteInput.text = ""
pasteInput.paste(itemProviders: [archiveFileProvider, archiveText])
let splitDeadline = Date().addingTimeInterval(3)
while pasteInput.text != "lodyUserBubble" && Date() < splitDeadline {
  RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
precondition(pasteInput.text == "lodyUserBubble", "A split webarchive pasteboard must insert the copied text")
print("Composer paste: webarchive selections stay text")

precondition(!ChatAttachment.shouldPromotePastedText("hello"))
precondition(!ChatAttachment.shouldPromotePastedText(String(repeating: "x", count: 1999)))
precondition(ChatAttachment.shouldPromotePastedText(String(repeating: "x", count: 2000)))
precondition(!ChatAttachment.shouldPromotePastedText((1...15).map { "line \($0)" }.joined(separator: "\n")))
precondition(ChatAttachment.shouldPromotePastedText((1...16).map { "line \($0)" }.joined(separator: "\n")))
let promoted = ChatAttachment.makePastedTextFile("long body")
precondition(promoted?.name == "Text.txt" && promoted?.isImage == false)
precondition((try? String(contentsOf: promoted!.url, encoding: .utf8)) == "long body")
print("Composer paste: long text promotion threshold passed")

let longBody = (1...16).map { "line \($0)" }.joined(separator: "\n")
let longProvider = NSItemProvider(object: longBody as NSString)
let longComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
longComposer.setComposerState(ready)
let longInput = descendants(longComposer).compactMap { $0 as? UITextView }.first!
let longSend = descendants(longComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-send" }!
longInput.paste(itemProviders: [longProvider])
let longDeadline = Date().addingTimeInterval(3)
while !longSend.isEnabled && Date() < longDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
precondition(longInput.text.isEmpty, "Long pasted text must not fill the composer")
precondition(longSend.isEnabled, "Long pasted text becomes a sendable text file")
LodyToastOverlay.shared.dismiss()
RunLoop.current.run(until: Date().addingTimeInterval(0.3))

let plainComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
plainComposer.setComposerState(ready)
let plainInput = descendants(plainComposer).compactMap { $0 as? UITextView }.first!
let plainAction = NSSelectorFromString("pastePlainText:")
let mixedPlainProvider = NSItemProvider(object: longBody as NSString)
for type in [UTType.rtf, UTType.flatRTFD, UTType.png] {
  mixedPlainProvider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
    completion(Data([0, 1, 2]), nil)
    return nil
  }
}
UIPasteboard.general.setItemProviders([mixedPlainProvider], localOnly: true, expirationDate: nil)
precondition(plainInput.canPerformAction(plainAction, withSender: nil))
let plainMenu = plainComposer.textView(plainInput, editMenuForTextIn: NSRange(location: 0, length: 0), suggestedActions: [])!
precondition(plainMenu.children.first?.title == LodyStrings.text("native.chat.composer.pastePlainText"))
plainInput.text = "before replace after"
plainInput.selectedRange = NSRange(location: 7, length: 7)
(plainInput as! ChatComposerInput).pastePlainText(from: [mixedPlainProvider])
let expectedPlain = "before " + longBody + " after"
let plainDeadline = Date().addingTimeInterval(3)
while plainInput.text != expectedPlain && Date() < plainDeadline {
  RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
precondition(plainInput.text == expectedPlain, "Plain paste must replace selection and keep long text inline: \(plainInput.text ?? "nil")")
var plainPayload: [String: Any] = [:]
plainComposer.onSend = { plainPayload = $0 }
plainComposer.perform(NSSelectorFromString("submit"))
precondition(plainPayload["text"] as? String == expectedPlain)
precondition((plainPayload["attachments"] as? [[String: String]])?.isEmpty == true,
  "Plain paste must ignore rich/image representations and bypass text-file promotion")
plainInput.isEditable = false
precondition(!plainInput.canPerformAction(plainAction, withSender: nil))
plainInput.isEditable = true
UIPasteboard.general.items = [[UTType.png.identifier: Data([0, 1, 2])]]
precondition(!plainInput.canPerformAction(plainAction, withSender: nil))
precondition(plainComposer.textView(plainInput, editMenuForTextIn: .init(location: 0, length: 0), suggestedActions: [])!.children.isEmpty)
print("Composer paste: explicit plain text ignores attachments and preserves selected-range insertion")

let undoComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
undoComposer.setComposerState(ready)
let undoWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
undoWindow.addSubview(undoComposer)
undoWindow.isHidden = false
let undoInput = descendants(undoComposer).compactMap { $0 as? UITextView }.first!
undoInput.text = "keep me"
undoInput.selectedRange = NSRange(location: (undoInput.text as NSString).length, length: 0)
undoInput.paste(itemProviders: [longProvider])
let undoDeadline = Date().addingTimeInterval(3)
var undo: UIButton?
while Date() < undoDeadline {
  undo = allWindows().flatMap(descendants).compactMap { $0 as? UIButton }
    .first { $0.accessibilityIdentifier == "lody.toast.undo" }
  if undo != nil { break }
  RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
precondition(undoInput.text == "keep me", "Long pasted text must leave the existing draft in place")
precondition(undo != nil, "Long paste must offer an undo toast action")
LodyToastOverlay.shared.performFrontAction()
let restoredDeadline = Date().addingTimeInterval(1)
while !undoInput.text.contains(longBody) && Date() < restoredDeadline {
  RunLoop.current.run(until: Date().addingTimeInterval(0.01))
}
precondition(undoInput.text.contains("keep me") && undoInput.text.contains(longBody),
  "Undo must insert the pasted text back into the composer")
precondition(undoInput.text.count == "keep me".count + longBody.count)
print("Composer paste: long text becomes a file with undo")

let movie = FileManager.default.temporaryDirectory.appendingPathComponent("IMG_3933.mov")
try! Data("video-bytes".utf8).write(to: movie)
let poster = FileManager.default.temporaryDirectory.appendingPathComponent("IMG_3933.png")
try! UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
  UIColor.red.setFill()
  context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
}.write(to: poster)
let videoProvider = NSItemProvider()
videoProvider.suggestedName = "IMG_3933"
videoProvider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
  completion(poster, false, nil)
  return nil
}
videoProvider.registerFileRepresentation(forTypeIdentifier: UTType.mpeg4Movie.identifier, fileOptions: [], visibility: .all) { completion in
  completion(movie, false, nil)
  return nil
}
let videoComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
videoComposer.setComposerState(ready)
let videoInput = descendants(videoComposer).compactMap { $0 as? UITextView }.first!
let videoSend = descendants(videoComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-send" }!
precondition(videoInput.canPaste([videoProvider]), "A copied video must enable Paste")
videoInput.paste(itemProviders: [videoProvider])
let videoDeadline = Date().addingTimeInterval(3)
while !videoSend.isEnabled && Date() < videoDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
precondition(videoSend.isEnabled, "Pasting a video must add a sendable attachment")
var videoAttachments: [[String: String]] = []
videoComposer.onSend = { videoAttachments = $0["attachments"] as! [[String: String]] }
for action in videoSend.actions(forTarget: videoComposer, forControlEvent: .touchUpInside) ?? [] {
  videoComposer.perform(NSSelectorFromString(action))
}
precondition(videoAttachments.first?["kind"] == "file", "A video must stay a file attachment, not an extracted poster image")
precondition(videoAttachments.first?["name"]?.hasSuffix(".mov") == true || videoAttachments.first?["name"]?.hasSuffix(".mp4") == true, "A pasted video must keep a video filename")
let videoURL = URL(string: videoAttachments.first!["uri"]!)!
precondition((try? Data(contentsOf: videoURL)) == Data("video-bytes".utf8), "A pasted video must keep the movie bytes, not a PNG poster")
print("Composer paste: video with an image poster stays a file")

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
precondition(handoffInput.text.isEmpty, "Failed sends stay in the transcript rather than jumping back into the composer")
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
print("Composer handoff: destination ownership, failed retention, no-overwrite and send identity passed")

let panelComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
actionWindow.addSubview(panelComposer)
panelComposer.sendHandoff = false
panelComposer.setComposerState(ready)
let panelInput = descendants(panelComposer).compactMap { $0 as? UITextView }.first!
let panelSend = descendants(panelComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-send" }!
panelInput.text = "Keep this draft visible"
panelComposer.textViewDidChange(panelInput)
var panelPayload: [String: Any] = [:]
panelComposer.onSend = { panelPayload = $0 }
for action in panelSend.actions(forTarget: panelComposer, forControlEvent: .touchUpInside) ?? [] {
  panelComposer.perform(NSSelectorFromString(action))
}
precondition(panelPayload["text"] as? String == "Keep this draft visible")
precondition(!ChatSendHandoff.isWaiting(id: panelPayload["id"] as! String),
  "Cross-container creation must not leave a flying copy in the window")
precondition(panelInput.text == "Keep this draft visible" && !panelInput.isEditable && !panelSend.isEnabled,
  "Cross-container sends retain and lock the source draft until dismissal")
panelComposer.restoreDraft(token: 1)
precondition(panelInput.text == "Keep this draft visible" && panelInput.isEditable && panelSend.isEnabled,
  "Rejected creation unlocks the same draft without duplicating it")
panelComposer.removeFromSuperview()

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

let retiredComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
retiredComposer.setComposerState(ready)
let retiredInput = descendants(retiredComposer).compactMap { $0 as? UITextView }.first!
let retiredSend = descendants(retiredComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-send" }!
retiredComposer.setPendingSend(transferred)
retiredComposer.clearPendingSend(id: "another-send")
precondition(!retiredSend.isEnabled, "A different send must not release the pending composer")
retiredComposer.clearPendingSend(id: transferred.id)
retiredInput.text = "已完成后继续发送"
retiredComposer.textViewDidChange(retiredInput)
precondition(retiredSend.isEnabled, "Retiring the published send must release the composer without a token transition")

let typingComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
typingComposer.setComposerState(ready)
let typingInput = descendants(typingComposer).compactMap { $0 as? UITextView }.first!
let typingSend = descendants(typingComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-send" }!
typingComposer.setPendingSend(transferred)
precondition(typingInput.isEditable && !typingSend.isEnabled, "Pending sends must keep input editable while preventing duplicate submission")
typingInput.text = "下一条新草稿"
typingComposer.textViewDidChange(typingInput)
typingComposer.setPendingSend(rejected)
precondition(typingInput.text == "下一条新草稿", "Failure must preserve the next draft while the transcript owns retry")
print("Composer continuity: editable pending input and no failed-draft jump passed")
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
// This executable has no render server; UI checks exercise real snapshot pixels.
final class HandoffWindow: UIWindow {
  override func resizableSnapshotView(from rect: CGRect, afterScreenUpdates afterUpdates: Bool, withCapInsets capInsets: UIEdgeInsets) -> UIView? { UIView(frame: rect) }
}
let throwWindow = HandoffWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
let throwInput = UITextView(frame: CGRect(x: 16, y: 700, width: 350, height: 60))
throwInput.text = "Preserve this message"
throwWindow.addSubview(throwInput)
let throwTarget = ChatMessageContent(frame: CGRect(x: 200, y: 100, width: 170, height: 45))
throwTarget.label.setText(NSAttributedString(string: throwInput.text))
throwWindow.addSubview(throwTarget)
onMain { ChatSendHandoff.begin(id: "cancel-throw", source: throwInput) }
onMain { ChatSendHandoff.hold(id: "cancel-throw", target: throwTarget) }
precondition(throwTarget.isHidden, "The destination must not duplicate the flying message")
onMain { ChatSendHandoff.deliver(id: "cancel-throw", to: throwTarget) }
let flyingText = throwWindow.subviews.compactMap { $0 as? ChatMessageContent }.first { $0 !== throwTarget }
precondition(flyingText != nil && flyingText!.label.bounds.width > 0 && flyingText!.label.bounds.height > 0,
  "The hidden background layer must not skip the flying text layout")
onMain {
  ChatSendHandoff.begin(id: "cancel-throw:attachment:offscreen", source: throwInput)
  ChatSendHandoff.cancelWaitingAttachments(id: "cancel-throw")
}
precondition(!ChatSendHandoff.hasWaitingAttachments(id: "cancel-throw") && throwTarget.isHidden,
  "Offscreen attachment cleanup must remove waiting copies without interrupting a visible flight")
onMain { ChatSendHandoff.cancel(id: "cancel-throw") }
RunLoop.current.run(until: Date().addingTimeInterval(0.5))
precondition(!throwTarget.isHidden, "Cancellation must reveal the destination")
precondition(throwWindow.subviews.count == 2, "Cancellation must remove every flight overlay")
print("Send throw: cancellation reveals target, removes overlays without replacing destination content")

var settledTurns: [String] = []
ChatSendHandoff.onSettled = { settledTurns.append($0) }
onMain { ChatSendHandoff.begin(id: "status-throw", source: throwInput) }
precondition(onMain { ChatSendHandoff.isInFlight(id: "status-throw") }, "A waiting copy is in flight")
precondition(settledTurns.isEmpty, "Flight start must not reveal status")
onMain {
  ChatSendHandoff.hold(id: "status-throw", target: throwTarget)
  ChatSendHandoff.deliver(id: "status-throw", to: throwTarget)
}
precondition(onMain { ChatSendHandoff.isInFlight(id: "status-throw") }, "Delivery must hide status until the throw lands")
precondition(settledTurns.isEmpty, "A moving copy must not reveal status")
onMain { ChatSendHandoff.cancel(id: "status-throw") }
precondition(onMain { !ChatSendHandoff.isInFlight(id: "status-throw") })
precondition(settledTurns == ["status-throw"], "Settling must reveal status once")
settledTurns.removeAll()
onMain {
  ChatSendHandoff.begin(id: "status-throw", source: throwInput)
  ChatSendHandoff.begin(id: "status-throw:attachment:a", source: throwInput)
}
precondition(onMain { ChatSendHandoff.isInFlight(id: "status-throw") })
onMain { ChatSendHandoff.cancel(id: "status-throw", includingAttachments: false) }
precondition(onMain { ChatSendHandoff.isInFlight(id: "status-throw") }, "Attachment copies keep the turn in flight")
precondition(settledTurns.isEmpty, "Status waits until every copy lands")
onMain { ChatSendHandoff.cancel(id: "status-throw:attachment:a") }
precondition(onMain { !ChatSendHandoff.isInFlight(id: "status-throw") })
precondition(settledTurns == ["status-throw"], "The last copy settling reveals status")
ChatSendHandoff.onSettled = nil
final class StatusHost: UIView, ChatSendHandoffSettling {
  var settled: [String] = []
  func handoffDidSettle(_ id: String) { settled.append(id) }
}
let statusHost = StatusHost(frame: throwWindow.bounds)
throwWindow.addSubview(statusHost)
let hostedInput = UITextView(frame: CGRect(x: 16, y: 700, width: 350, height: 60))
statusHost.addSubview(hostedInput)
onMain { ChatSendHandoff.begin(id: "owner-throw", source: hostedInput) }
onMain { ChatSendHandoff.cancel(id: "owner-throw") }
precondition(statusHost.settled == ["owner-throw"], "The transcript host must insert status after its own throw settles")
print("Send throw: status waits until every copy settles")

let relayComposer = ChatComposerView(frame: composer.frame)
relayComposer.setComposerState(ready)
relayComposer.setInitialDraft("Keep until adopted")
let relayInput = descendants(relayComposer).compactMap { $0 as? UITextView }.first!
var relayPayload: [String: Any]?
var relayDispatches = 0
relayComposer.prepareSend = { payload in
  relayPayload = payload
  relayComposer.relaying = true
  relayDispatches += 1
  return true
}
relayComposer.perform(NSSelectorFromString("submit"))
relayComposer.perform(NSSelectorFromString("submit"))
relayComposer.setComposerState(#"{"editable":true,"canSend":false,"sending":true}"#)
precondition(relayInput.text == "Keep until adopted" && relayDispatches == 1,
  "Preparing a destination must preserve the draft and dispatch only once")
relayComposer.onSend = { _ in preconditionFailure("Adoption cannot dispatch the creation twice") }
relayComposer.commitSend(relayPayload!)
precondition(relayInput.text.isEmpty, "Only adoption consumes the source draft")
relayComposer.restoreDraft(token: 1)
precondition(relayInput.text == "Keep until adopted", "An adopted send must remain restorable")
print("Composer relay: prepare preserves draft, adoption consumes once, failure restores")

let queueComposer = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 390, height: 244))
let runningState = #"{"editable":true,"canSend":true,"sending":false,"running":true,"canStop":true,"notice":"","reconnect":false,"placeholder":"任务"}"#
queueComposer.setComposerState(runningState)
let queueInput = descendants(queueComposer).compactMap { $0 as? UITextView }.first!
let queueSend = descendants(queueComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-stop" }!
var stopCalls = 0
var queuePayload: [String: Any] = [:]
queueComposer.onStop = { stopCalls += 1 }
queueComposer.onSend = { queuePayload = $0 }
@MainActor func tapQueueAction() {
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

let guideWindow = HandoffWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
let guideComposer = ChatComposerView(frame: CGRect(x: 0, y: 600, width: 390, height: 244))
guideWindow.addSubview(guideComposer)
guideWindow.isHidden = false
guideComposer.setComposerState(#"{"editable":true,"canSend":true,"sending":false,"running":true,"canStop":true,"steerInterrupts":false,"queuedMessageBehavior":"guide","notice":"","reconnect":false,"placeholder":"任务"}"#)
let guideInput = descendants(guideComposer).compactMap { $0 as? UITextView }.first!
let guideSend = descendants(guideComposer).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-stop" || $0.accessibilityIdentifier == "session-send" }!
var guidePayload: [String: Any] = [:]
guideComposer.onSend = { guidePayload = $0 }
guideInput.text = "Steer now"
guideComposer.textViewDidChange(guideInput)
precondition(guideSend.accessibilityIdentifier == "session-send" && guideSend.isEnabled, "Guide still sends from a running composer")
@MainActor func tapGuideAction() {
  for action in guideSend.actions(forTarget: guideComposer, forControlEvent: .touchUpInside) ?? [] {
    guideComposer.perform(NSSelectorFromString(action))
  }
}
tapGuideAction()
precondition(guidePayload["queue"] as? Bool == false, "Guide must not mark the send as queued")
precondition(guidePayload["guide"] as? Bool == true, "Guide must mark the send for steer delivery")
precondition(guideInput.text.isEmpty, "Guide send must clear the draft")
precondition(onMain { ChatSendHandoff.isWaiting(id: guidePayload["id"] as! String) }, "Guide send must fly from the composer, not sit in the queue")
onMain { ChatSendHandoff.cancel(id: guidePayload["id"] as! String) }
print("Guide composer: busy send skips the queue and starts a straight handoff")

// A steered queue row hands its frame to the send animation instead of vanishing.
let steerWindow = HandoffWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
let steerComposer = ChatComposerView(frame: CGRect(x: 0, y: 600, width: 390, height: 244))
steerWindow.addSubview(steerComposer)
steerWindow.isHidden = false
steerComposer.setComposerState(runningState)
steerComposer.setQueue([ChatQueuedDraft(id: "s1", text: "Steer me"), ChatQueuedDraft(id: "s2", text: "Stay queued")])
steerComposer.layoutIfNeeded()
steerComposer.setQueue([ChatQueuedDraft(id: "s2", text: "Stay queued")])
precondition(onMain { ChatSendHandoff.isWaiting(id: "s1") }, "A steered row must start its flight before leaving the queue")
precondition(onMain { !ChatSendHandoff.isWaiting(id: "s2") }, "A row that stays queued must not fly")
let steerTarget = ChatMessageContent(frame: CGRect(x: 200, y: 120, width: 170, height: 45))
steerTarget.label.setText(NSAttributedString(string: "Steer me"))
steerWindow.addSubview(steerTarget)
onMain { ChatSendHandoff.hold(id: "s1", target: steerTarget) }
onMain { ChatSendHandoff.deliver(id: "s1", to: steerTarget) }
let steerFlight = steerWindow.subviews.compactMap { $0 as? ChatMessageContent }.first { $0 !== steerTarget }
precondition(steerFlight?.layer.animation(forKey: "throw.scale") == nil, "A steered message slides straight, without the throw squash")
precondition(steerFlight?.layer.animation(forKey: "throw.position") != nil, "A steered message must animate to its landed row")
onMain { ChatSendHandoff.cancel(id: "s1") }
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
  glassAttachGlyph != nil && glassAttach.image(for: .normal) == nil
    && glassAttach.configuration?.image == nil,
  "Liquid Glass must own a stable Add glyph view so UIButton relayout cannot reset its scale"
)
glassComposer.setMentionItems("[]")
let restingAttachGlyphSize = glassAttachGlyph!.bounds.size
precondition(
  abs(restingAttachGlyphSize.width - (glassAttachGlyph!.image?.size.width ?? 0)) < 0.5,
  "Resting Add plus must keep its symbol size"
)
precondition(glassInput.becomeFirstResponder(), "The glass composer input must accept focus")
precondition(glassAttachSurface.effect is UIGlassEffect
  && !glassAttachSurface.isDescendant(of: glassInputSurface),
  "The opening transition must retain both glass surfaces until their native merge completes")
precondition(
  glassAttachGlyph!.alpha == 1 && glassAttach.isDescendant(of: glassAttachSurface),
  "Opening must keep the Add plus visible on its attach glass"
)
RunLoop.current.run(until: Date().addingTimeInterval(0.35))
glassComposer.layoutIfNeeded()

let mentionEntry = descendants(glassComposer).first { $0.accessibilityIdentifier == "session-mention" }!
glassComposer.setComposerState(ready)
precondition(!mentionEntry.isHidden, "Ordinary composer state updates must not erase the separately loaded reference catalog")
let focusedInputFrame = glassInputSurface.convert(glassInputSurface.bounds, to: glassComposer)
let focusedAttachFrame = glassAttach.convert(glassAttach.bounds, to: glassComposer)
precondition(glassAttach.isDescendant(of: glassInputSurface) && !glassAttachSurface.isUserInteractionEnabled,
  "Merged Add must use the input's interaction surface, with one 44-point action")
glassInputSurface.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
let pressedAttachFrame = glassAttach.convert(glassAttach.bounds, to: glassComposer)
precondition(abs(pressedAttachFrame.width - focusedAttachFrame.width * 1.05) < 0.5,
  "Pressing the input glass must scale the merged Add along with its content")
glassInputSurface.transform = .identity
precondition(
  abs(focusedInputFrame.minX + 6 - focusedAttachFrame.minX) < 0.5
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
  abs(attachInset - 28) < 0.5
    && abs(sendInset - 24) < 0.5
    && abs(baselineDelta) < 0.5,
  "Focused Add must have a 28-point inset and Send a 24-point inset on the same baseline; "
    + "got add \(attachInset), send \(sendInset), baseline \(baselineDelta)"
)
let sendVisualView = descendants(glassSend).first {
  $0.accessibilityIdentifier == "session-action-visual"
}!
let sendGlyph = descendants(sendVisualView).compactMap { $0 as? UIImageView }.first {
  !$0.isHidden && $0.image != nil
}!
let focusedGlyph = descendants(glassAttach).compactMap { $0 as? UIImageView }.first {
  $0.accessibilityIdentifier == "session-attach-focused-glyph"
}!
let mergedImage = focusedGlyph.image!
let focusedAttachGlyphSize = focusedGlyph.bounds.size
precondition(
  abs(focusedAttachGlyphSize.width - mergedImage.size.width) < 0.5
    && abs(focusedAttachGlyphSize.height - mergedImage.size.height) < 0.5
    && focusedGlyph.alpha == 1,
  "Focus must render the regular glyph at its intended size"
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
glassInput.resignFirstResponder()
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
glassComposer.layoutIfNeeded()
precondition(glassAttachSurface.effect is UIGlassEffect
  && !glassAttachSurface.isDescendant(of: glassInputSurface),
  "Leaving focus must restore Add's separate interactive glass")
precondition(glassAttachGlyph!.alpha == 1 && glassAttach.isDescendant(of: glassAttachSurface)
  && abs(glassAttachGlyph!.bounds.width - restingAttachGlyphSize.width) < 0.5,
  "Leaving focus must restore the separate medium glyph and its original action host")
glassInput.becomeFirstResponder()
RunLoop.current.run(until: Date().addingTimeInterval(0.05))
glassInput.resignFirstResponder()
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
precondition(glassAttachSurface.effect is UIGlassEffect
  && !glassAttachSurface.isDescendant(of: glassInputSurface),
  "Cancelling an opening must not later move the separate Add into the input")

// A trigger belongs to the active caret token, never email or selected prose.
assert(ChatMentionPanel.activeRange(text: "😀 @auth", selection: NSRange(location: 8, length: 0)) == NSRange(location: 3, length: 5))
assert(ChatMentionPanel.activeRange(text: "mail@host", selection: NSRange(location: 9, length: 0)) == nil)
assert(ChatMentionPanel.activeRange(text: "@auth ", selection: NSRange(location: 6, length: 0)) == nil)
assert(ChatMentionPanel.activeRange(text: "@auth", selection: NSRange(location: 1, length: 3)) == nil)

assert(ChatMentionPanel.activeRange(text: "😀 $auth", selection: NSRange(location: 8, length: 0)) == NSRange(location: 3, length: 5))
assert(ChatMentionPanel.activeRange(text: "/compact", selection: NSRange(location: 8, length: 0)) == NSRange(location: 0, length: 8))
assert(ChatMentionPanel.activeRange(text: "read /tmp", selection: NSRange(location: 9, length: 0)) == nil)
assert(ChatMentionPanel.activeRange(text: "/tmp/file", selection: NSRange(location: 9, length: 0)) == nil)

// A cancelled exit must not later hide a reopened picker or clear its layout space.
let referenceWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
let referenceInput = UITextView(frame: CGRect(x: 0, y: 400, width: 390, height: 60))
let referencePanel = ChatMentionPanel(frame: CGRect(x: 16, y: 280, width: 358, height: 112))
referenceWindow.addSubview(referenceInput)
referenceWindow.addSubview(referencePanel)
referenceWindow.isHidden = false
precondition(referenceInput.becomeFirstResponder())
let referenceItems = [ChatMentionItem(path: "src", name: "src", kind: "directory", subtitle: "Project files")]
@MainActor func referenceText(_ text: String) {
  referenceInput.text = text
  referenceInput.selectedRange = NSRange(location: (text as NSString).length, length: 0)
  referencePanel.update(input: referenceInput, items: referenceItems)
}
referenceText("@")
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
precondition(!referencePanel.isHidden && referencePanel.alpha == 1)
referenceText("")
precondition(!referencePanel.isHidden && referencePanel.panelHeight > 0 && !referencePanel.isUserInteractionEnabled,
             "An exiting panel must retain its content and layout space until its animation finishes")
RunLoop.current.run(until: Date().addingTimeInterval(0.03))
referenceText("@")
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
precondition(!referencePanel.isHidden && referencePanel.alpha == 1 && referencePanel.panelHeight > 0,
             "An interrupted exit must leave the reopened panel visible and usable")
referenceText("ordinary text")
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
precondition(referencePanel.isHidden && referencePanel.panelHeight == 0,
             "A completed exit must release the reserved layout space")
referenceInput.text = "@"
referenceInput.selectedRange = NSRange(location: 1, length: 0)
referencePanel.update(input: referenceInput, items: [])
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
precondition(!referencePanel.isHidden && referencePanel.panelHeight > 0,
             "The real reference entry must remain usable while its catalog is loading or empty")
let referenceList = descendants(referencePanel).compactMap { $0 as? UICollectionView }.first!
referencePanel.collectionView(referenceList, didSelectItemAt: IndexPath(item: 1, section: 0))
let skill = ChatMentionItem(path: "/Users/test/skills/auth/SKILL.md", name: "auth-review", kind: "skill", subtitle: "Auth", insertText: "$auth-review")
referencePanel.finishBrowse(path: skill.path, selectedItem: skill)
precondition(referenceInput.text == skill.insertText! + " ",
             "A remotely selected skill must insert only its short token even when the inline catalog has not arrived")
print("References: empty catalog browse and remote skill insertion passed")
precondition(referenceInput.becomeFirstResponder())
referenceInput.text = "/"
referenceInput.selectedRange = NSRange(location: 1, length: 0)
referencePanel.update(input: referenceInput, items: [skill])
RunLoop.current.run(until: Date().addingTimeInterval(0.4))
precondition(referencePanel.isHidden, "An agent without commands must not show an empty slash menu")
let command = ChatMentionItem(path: "compact", name: "compact", kind: "cmd", subtitle: "Compact", insertText: "/compact")
referencePanel.update(input: referenceInput, items: [skill, command])
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
precondition(!referencePanel.isHidden)
precondition(referencePanel.collectionView(referenceList, numberOfItemsInSection: 0) == 1, "Slash must open commands directly")
referencePanel.collectionView(referenceList, didSelectItemAt: IndexPath(item: 0, section: 0))
precondition(referenceInput.text == "/compact ")
referenceInput.text = "$"
referenceInput.selectedRange = NSRange(location: 1, length: 0)
referencePanel.update(input: referenceInput, items: [skill, command])
precondition(referencePanel.collectionView(referenceList, numberOfItemsInSection: 0) == 1, "Dollar must open skills directly")
referencePanel.collectionView(referenceList, didSelectItemAt: IndexPath(item: 0, section: 0))
precondition(referenceInput.text == "$auth-review ")

referenceText("@")
referencePanel.removeFromSuperview()
RunLoop.current.run(until: Date().addingTimeInterval(0.25))
precondition(referencePanel.isHidden && referencePanel.panelHeight == 0,
             "Removing the host must cancel a queued entrance")
print("Reference motion: delayed removal, interrupted exit, and host teardown passed")

let prDraft = ChatComposerView(frame: CGRect(x: 0, y: 0, width: 402, height: 180))
prDraft.setInitialDraft("Existing draft")
var savedPRDraft = ""
prDraft.onDraftChange = { savedPRDraft = $0 }
prDraft.appendDraft(#"{"id":"pr-1","text":"Investigate CI"}"#)
precondition(savedPRDraft == "Existing draft\n\nInvestigate CI")
prDraft.appendDraft(#"{"id":"pr-1","text":"Investigate CI"}"#)
precondition(savedPRDraft == "Existing draft\n\nInvestigate CI", "A prop replay must not append twice")
print("PR investigation: existing draft preserved, appended text saved and prop replay ignored")

let materialWindow = HandoffWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
let materialComposer = ChatComposerView(frame: CGRect(x: 0, y: 500, width: 390, height: 200))
materialWindow.addSubview(materialComposer)
materialWindow.isHidden = false
materialComposer.setComposerState(ready)
var materialHeight: CGFloat = 0
materialComposer.onHeightChange = { materialHeight = $0 }
materialComposer.setQueue([ChatQueuedDraft(id: "material-queue", text: "Last queued turn")])
materialComposer.layoutIfNeeded()
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
let materialQueue = descendants(materialComposer).first { $0.accessibilityIdentifier == "session-queue" } as! CKGlassSurface
let withQueue = materialHeight
materialComposer.setQueue([])
precondition(!materialQueue.isHidden && !materialQueue.isUserInteractionEnabled && materialHeight == withQueue,
  "The last queue card must keep its space until its glass leaves")
precondition(materialComposer.retiringQueueHeight == 44,
  "Retiring glass must stop reserving transcript space before the message flies")
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
precondition(materialQueue.isHidden && materialHeight == withQueue - 44 && materialComposer.retiringQueueHeight == 0)
ChatSendHandoff.cancel(id: "material-queue")

materialComposer.setInitialAttachments(#"[{"id":"remove-a","name":"a.txt","uri":"file:///tmp/a.txt","kind":"file"},{"id":"keep-b","name":"b.txt","uri":"file:///tmp/b.txt","kind":"file"}]"#)
materialComposer.layoutIfNeeded()
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
let materialBar = descendants(materialComposer).compactMap { $0 as? ChatAttachmentBar }.first!
let retained = descendants(materialBar).compactMap { $0 as? UIButton }.first {
  $0.accessibilityLabel == LodyStrings.text("native.chat.attachment.preview", ["name": "b.txt"])
}!
@MainActor func removeMaterialAttachment(_ name: String) {
  let button = descendants(materialBar).compactMap { $0 as? UIButton }.first {
    $0.accessibilityLabel == LodyStrings.text("native.chat.attachment.remove", ["name": name])
  }!
  button.sendActions(for: .touchUpInside)
}
removeMaterialAttachment("a.txt")
precondition(materialBar.attachmentFrame(id: "remove-a") == nil && retained.window != nil,
  "Deleting a pill updates the draft immediately and preserves the other native control")
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
precondition(materialBar.attachmentFrame(id: "keep-b") != nil)
let withAttachment = materialHeight
removeMaterialAttachment("b.txt")
precondition(materialBar.hasVisiblePills && materialHeight == withAttachment,
  "The final attachment reserves its height through dematerialization")
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
precondition(!materialBar.hasVisiblePills && materialHeight == withAttachment - 42)
print("Glass hosts: queue and final attachment retain their space through exit; unrelated pills retain identity")

let quickComposer = ChatComposerView(frame: CGRect(x: 0, y: 600, width: 390, height: 108))
materialWindow.addSubview(quickComposer)
let quickInput = descendants(quickComposer).compactMap { $0 as? UITextView }.first!
let quickStrip = descendants(quickComposer).compactMap { $0 as? ChatQuickRepliesView }.first!
let quickMessage = "Commit and push the changes from this task."
let quickReady: [String: Any] = [
  "editable": true, "canSend": true, "sending": false, "running": false,
  "notice": "", "reconnect": false, "placeholder": "Message",
  "quickReplies": [["id": "commit", "label": "Commit & Push", "message": quickMessage]],
]
@MainActor func quickState(_ changes: [String: Any] = [:]) {
  let json = try! JSONSerialization.data(withJSONObject: quickReady.merging(changes) { _, value in value })
  quickComposer.setComposerState(String(decoding: json, as: UTF8.self))
  quickComposer.layoutIfNeeded()
}
quickState()
let quickChipHeight = ChatQuickRepliesView.chipHeight
let connectingChipHeight = ChatQuickRepliesView.titleFont.lineHeight + 12
precondition(abs(quickChipHeight - connectingChipHeight - 4) < 0.5,
  "Quick-reply chips must sit four points above the connecting overlay height")
precondition(!quickStrip.isHidden && abs(quickStrip.bounds.height - quickChipHeight) < 0.5)
let quickButton = descendants(quickStrip).compactMap { $0 as? UIButton }.first!
let singleChip = quickButton.convert(quickButton.bounds, to: quickStrip)
precondition(abs(singleChip.height - quickChipHeight) < 0.5)
precondition(singleChip.width < 200 && singleChip.maxX < quickStrip.bounds.width - 8,
  "A single chip must follow its title instead of filling the composer")
var quickSends: [[String: Any]] = []
quickComposer.onSend = { quickSends.append($0) }
for draft in ["Existing draft", " "] {
  quickInput.text = draft
  quickComposer.textViewDidChange(quickInput)
  quickButton.sendActions(for: .touchUpInside)
  precondition(quickStrip.isHidden && quickStrip.accessibilityElementsHidden && quickInput.text == draft && quickSends.isEmpty,
    "Quick replies must never replace even a whitespace-only draft")
}
quickInput.text = ""
quickComposer.textViewDidChange(quickInput)
let quickUnavailableStates: [[String: Any]] = [
  ["running": true], ["sending": true], ["canSend": false], ["editable": false],
  ["stopping": true], ["controlling": true], ["connection": "paused"], ["quickReplies": []],
]
for (index, unavailable) in quickUnavailableStates.enumerated() {
  quickState(unavailable)
  quickButton.sendActions(for: .touchUpInside)
  precondition(quickStrip.isHidden && quickSends.isEmpty, "A stale quick-reply tap must not send while unavailable")
  // The ordinary sending prop captures a pending draft, just as production does.
  quickComposer.clearDraft(token: index + 1)
}
quickState()
quickComposer.setInitialAttachments(#"[{"id":"quick-file","name":"quick.txt","uri":"file:///tmp/quick.txt","kind":"file"}]"#)
precondition(quickStrip.isHidden, "An attachment-only draft must hide quick replies")
let quickRemove = descendants(quickComposer).compactMap { $0 as? UIButton }.first {
  $0.accessibilityLabel == LodyStrings.text("native.chat.attachment.remove", ["name": "quick.txt"])
}!
quickRemove.sendActions(for: .touchUpInside)
quickComposer.setQueue([ChatQueuedDraft(id: "quick-queued", text: "Waiting")])
precondition(quickStrip.isHidden, "Queued work must not expose an idle shortcut")
quickComposer.setQueue([])
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
quickState()
let activeQuickButton = descendants(quickStrip).compactMap { $0 as? UIButton }.first!
activeQuickButton.sendActions(for: .touchUpInside)
activeQuickButton.sendActions(for: .touchUpInside)
precondition(quickSends.count == 1 && quickSends[0]["text"] as? String == quickMessage,
  "A quick reply sends its full message once through the ordinary send event")
precondition(quickSends[0]["queue"] as? Bool == false && quickSends[0]["guide"] as? Bool == false)
precondition(quickStrip.isHidden && quickInput.text.isEmpty)
quickComposer.restoreDraft(token: 1)
precondition(quickInput.text == quickMessage && quickStrip.isHidden,
  "Rejected quick replies must restore the original message, not silently send again")
quickInput.text = ""
quickComposer.textViewDidChange(quickInput)
quickState([
  "quickReplies": [
    ["id": "ok", "label": "OK", "message": "OK"],
    ["id": "go", "label": "Commit & Push", "message": "Go"],
  ],
])
let huggingButtons = descendants(quickStrip).compactMap { $0 as? UIButton }
precondition(huggingButtons.count == 2)
let okChip = huggingButtons[0].convert(huggingButtons[0].bounds, to: quickStrip)
let longChip = huggingButtons[1].convert(huggingButtons[1].bounds, to: quickStrip)
precondition(okChip.width < longChip.width)
precondition(okChip.width < 100, "A short label must not stretch toward an equal share of the row")
precondition(longChip.maxX < quickStrip.bounds.width,
  "Two compact chips must leave trailing space instead of filling the composer")
let manyReplies = (1...8).map { ["id": "r\($0)", "label": "Reply \($0)", "message": "Reply \($0)"] }
quickState(["quickReplies": manyReplies])
precondition(quickStrip.contentSize.width > quickStrip.bounds.width,
  "Overflowing chips must scroll horizontally")
print("Quick replies: idle-only visibility, draft/attachment preservation, queue gating, single send and failed draft recovery passed")
