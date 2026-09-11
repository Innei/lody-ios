import UIKit

let mentionText = "#30 @src/app.ts @\"folder/my file.swift\" use /review [Skill Path](/skills/review/SKILL.md)"
let mentionSource = NSAttributedString(string: mentionText, attributes: [.font: UIFont.systemFont(ofSize: 17)])
let richMentions = ChatUserMentions.decorate(mentionSource, repository: "Innei/lody-ios", traits: .current)
precondition(mentionSource.string == mentionText, "Decorating must not change the stored or copied prompt")
precondition(richMentions.string.contains("$review") && !richMentions.string.contains("[Skill Path]"))
let mentionView = ChatTextView(frame: CGRect(x: 0, y: 0, width: 180, height: 400))
mentionView.setText(richMentions)
var mentionOpened = ""
mentionView.onLink = { mentionOpened = $0 }
precondition(mentionView.link(at: CGPoint(x: 5, y: 12)) == "https://github.com/Innei/lody-ios/issues/30")
precondition(mentionView.linkActions.map(\.name) == ["#30", "@src/app.ts", "@folder/my file.swift", "$review"])
precondition(mentionView.linkActions.last!.actionHandler!(mentionView.linkActions.last!))
precondition(mentionOpened == "/skills/review/SKILL.md", "The skill must open its file, not execute an instruction")
mentionView.linkHitHeight = 0
precondition(mentionView.link(at: CGPoint(x: 5, y: 12)) == nil, "Faded or collapsed text must not intercept touches")
let literal = "`#30 @src/app.ts` `` @src/app.ts #30 `` ```\n@src/app.ts\n#30\n``` https://example.org/#30 someone@example.org \\#30 \\@src/app.ts @session:id @role:id"
let unchanged = ChatUserMentions.decorate(NSAttributedString(string: literal), repository: "Innei/lody-ios", traits: .current)
precondition(unchanged.string == literal, "Code, URLs, emails, escaped text and other mention types stay literal")
let localNumber = ChatUserMentions.decorate(NSAttributedString(string: "#30"), repository: "", traits: .current)
precondition(localNumber.string == "#30", "A number cannot link to a repository outside this session")
let punctuation = ChatUserMentions.decorate(NSAttributedString(string: "@file.swift, then @Dockerfile."), repository: "", traits: .current)
precondition(punctuation.string.replacingOccurrences(of: "\u{FFFC}\u{00a0}", with: "") == "@file.swift, then @Dockerfile.", "Reference styling preserves adjacent punctuation")
let longPath = "@src/" + String(repeating: "long-segment/", count: 12) + "View.swift"
mentionView.setText(ChatUserMentions.decorate(NSAttributedString(string: longPath, attributes: [.font: UIFont.systemFont(ofSize: 17)]), repository: "", traits: .current))
let mentionSize = mentionView.sizeThatFits(CGSize(width: 180, height: 1000))
precondition(mentionSize.width <= 181 && mentionSize.height > 44, "Long file references wrap within the message width")
print("User mentions: rich labels, file and GitHub targets, VoiceOver actions, wrapping and literal-text boundaries passed")

// A partially offscreen text view must retain every line when scrolling exposes it.
let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 400))
let view = ChatTextView(frame: CGRect(x: 0, y: 350, width: 350, height: 600))
window.addSubview(view)
view.setText(NSAttributedString(string: (1...20).map { "Line \($0): scrolling keeps this content" }.joined(separator: "\n"), attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.black]))
func draw() -> Data {
  UIGraphicsImageRenderer(size: view.bounds.size).image { context in
    UIColor.white.setFill()
    context.fill(view.bounds)
    view.draw(view.bounds)
  }.pngData()!
}
let initiallyClipped = draw()
view.frame.origin.y = 0
let exposedByScrolling = draw()
precondition(initiallyClipped == exposedByScrolling, "Text drawing must not depend on the current scroll position")
print("Chat render: offscreen lines remain drawn across scrolling")

let shineView = ChatTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 20))
window.addSubview(shineView)
shineView.setText(NSAttributedString(string: "正在处理", attributes: [
  .font: UIFont.systemFont(ofSize: 13),
  .foregroundColor: UIColor.systemBlue,
]))
func shineSnapshot() -> Data {
  UIGraphicsImageRenderer(size: shineView.bounds.size).image { context in
    UIColor.white.setFill()
    context.fill(shineView.bounds)
    shineView.draw(shineView.bounds)
  }.pngData()!
}
shineView.setShine(false)
let rest = shineSnapshot()
shineView.setShine(true)
// Sample a full cycle: its offscreen phase can legitimately match resting text.
let frames = (0..<10).map { _ in
  Thread.sleep(forTimeInterval: 0.16)
  return shineSnapshot()
}
if !UIAccessibility.isReduceMotionEnabled {
  precondition(frames.contains { $0 != rest }, "Shine must change glyph brightness")
  precondition(Set(frames).count > 1, "Shine must travel across glyphs")
}
shineView.setShine(false)
let still = shineSnapshot()
Thread.sleep(forTimeInterval: 0.4)
precondition(still == shineSnapshot(), "Completed process text must stay still")
print("Chat render: process shine travels across running glyphs")

let durationRow = ChatRow(
  id: "turn:duration",
  entryID: "reply",
  kind: "duration",
  text: "Working for 3s",
  running: true,
  workDurationMs: 3_000
)
let durationCell = ChatCell(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
window.addSubview(durationCell)
durationCell.configure(durationRow, text: NSAttributedString(string: durationRow.text))
durationCell.layoutIfNeeded()
precondition(!durationCell.spinner.isAnimating, "The duration label must not show a loading indicator")
precondition(ChatCell.leading(durationRow) == 0, "The duration label must align to the full row's leading edge")
precondition(ChatCell.textWidth(durationRow, width: 320) == 320,
  "The duration label must not reserve a trailing indicator slot")
print("Chat render: duration label is static and uses the full row width")

let separatorColor = UIColor.separator.resolvedColor(with: durationCell.traitCollection).cgColor
let durationSeparator = durationCell.contentView.subviews.first {
  $0.backgroundColor?.resolvedColor(with: durationCell.traitCollection).cgColor == separatorColor
}
precondition(durationSeparator?.frame.minX == 0 && durationSeparator?.frame.maxX == 320,
  "The duration separator must span the full row width")
precondition(durationSeparator?.frame.maxY == durationCell.contentView.bounds.maxY,
  "The duration separator must sit directly below the label row")
print("Chat render: duration separator spans the row below the label")

func chromeHeight(_ row: ChatRow, text: String, width: CGFloat, traits: UITraitCollection) -> CGFloat {
  let view = ChatTextView()
  view.setText(NSAttributedString(string: text, attributes: [
    .font: ChatCell.messageFont(for: row, compatibleWith: traits),
  ]))
  return view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
}

let spacingTraits = durationCell.traitCollection
let durationTextHeight = chromeHeight(durationRow, text: durationRow.text, width: 320, traits: spacingTraits)
precondition(
  ChatRowPadding.durationBottom == ChatRowPadding.content / 2,
  "The work-duration trailing gap must be half the body-to-process gap"
)
precondition(
  ChatCell.rowExtra(for: durationRow) == ChatRowPadding.content + ChatRowPadding.durationBottom,
  "The duration row must size to that half-gap instead of the body-text padding"
)
let durationNatural = ChatCell(frame: CGRect(
  x: 0,
  y: 0,
  width: 320,
  height: durationTextHeight + ChatCell.rowExtra(for: durationRow)
))
window.addSubview(durationNatural)
durationNatural.configure(durationRow, text: NSAttributedString(string: durationRow.text, attributes: [
  .font: ChatCell.messageFont(for: durationRow, compatibleWith: spacingTraits),
]))
durationNatural.layoutIfNeeded()
precondition(
  abs((durationNatural.bounds.height - durationNatural.label.frame.maxY) - ChatRowPadding.durationBottom) < 0.6,
  "The gap below the work-duration label must be half the gap between body text and the process row"
)
print("Chat render: duration bottom gap is half the text-to-process gap")

let answerRow = ChatRow(id: "reply:answer", entryID: "reply", kind: "text", text: "计时完成。")
precondition(
  ChatRowPadding.top(kind: "text", previousKind: "duration") == ChatRowPadding.textBelowDuration,
  "Body copy under the duration hairline must use a full paragraph inset"
)
precondition(
  ChatCell.rowExtra(for: answerRow, previousKind: "duration")
    == ChatRowPadding.textBelowDuration + ChatRowPadding.content,
  "A text row after duration must grow by that inset, not the 44 pt button floor"
)
precondition(
  ChatCell.rowExtra(for: answerRow, previousKind: "summary") == ChatRowPadding.content * 2,
  "Ordinary body copy keeps the compact text padding"
)
print("Chat render: text below the duration rule uses a paragraph inset")

func resolved(_ color: UIColor?, traits: UITraitCollection) -> CGColor? {
  color?.resolvedColor(with: traits).cgColor
}

let thoughtRow = ChatRow(
  id: "reply:thought",
  entryID: "reply",
  kind: "thought",
  text: "思考过程",
  symbol: "brain"
)
let thoughtCell = ChatCell(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
window.addSubview(thoughtCell)
thoughtCell.configure(thoughtRow, text: NSAttributedString(string: thoughtRow.text, attributes: [
  .font: UIFont.systemFont(ofSize: 15),
]))
thoughtCell.layoutIfNeeded()
precondition(thoughtCell.icon.frame.minX >= 2, "Thought icon must inset from the clipped leading edge")
precondition(thoughtCell.icon.frame.width >= 20, "Thought icon slot must fit the brain symbol")
precondition(thoughtCell.icon.frame.maxX <= ChatCell.leading(thoughtRow),
  "Thought icon must stay inside the reserved leading gutter")
precondition((thoughtCell.icon.image?.size.width ?? .greatestFiniteMagnitude) <= thoughtCell.icon.bounds.width,
  "Thought icon must not overflow its slot")
let toolRow = ChatRow(
  id: "reply:read",
  entryID: "reply",
  kind: "tool_call",
  text: "读取文件",
  symbol: "doc.text.magnifyingglass"
)
let toolCell = ChatCell(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
window.addSubview(toolCell)
toolCell.configure(toolRow, text: NSAttributedString(string: toolRow.text, attributes: [
  .font: UIFont.systemFont(ofSize: 13),
]))
toolCell.layoutIfNeeded()
let thoughtWidth = thoughtCell.icon.image?.size.width ?? .greatestFiniteMagnitude
let toolWidth = toolCell.icon.image?.size.width ?? 0
precondition(abs(thoughtWidth - toolWidth) <= 2,
  "Thought and tool icons must share the same optical size, thought=\(thoughtWidth) tool=\(toolWidth)")
print("Chat render: thought icon stays inside the leading gutter")

func summaryRow(running: Bool, attention: Bool) -> ChatRow {
  ChatRow(
    id: "reply:process",
    entryID: "reply",
    kind: "summary",
    text: "执行过程",
    symbol: "circle.fill",
    actionable: true,
    running: running,
    attention: attention
  )
}

func summaryCell(for row: ChatRow) -> ChatCell {
  let cell = ChatCell(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
  window.addSubview(cell)
  cell.configure(row, text: NSAttributedString(string: row.text, attributes: [
    .font: UIFont.systemFont(ofSize: 13),
  ]))
  cell.layoutIfNeeded()
  return cell
}

let runningSummary = summaryCell(for: summaryRow(running: true, attention: false))
let doneSummary = summaryCell(for: summaryRow(running: false, attention: false))
let failedSummary = summaryCell(for: summaryRow(running: false, attention: true))
let traits = runningSummary.traitCollection
precondition(resolved(runningSummary.icon.tintColor, traits: traits) == resolved(.systemBlue, traits: traits),
  "A live process pip must be system blue")
precondition(resolved(doneSummary.icon.tintColor, traits: traits) == resolved(.secondaryLabel, traits: traits),
  "A finished process pip must use secondary label")
precondition(resolved(failedSummary.icon.tintColor, traits: traits) == resolved(.systemOrange, traits: traits),
  "A failed or pending process pip must be system orange")
precondition((runningSummary.icon.image?.size.width ?? .greatestFiniteMagnitude) < (thoughtCell.icon.image?.size.width ?? 0),
  "The process status pip must be smaller than thought and tool icons")
precondition(ChatCell.leading(doneSummary.row!) == 12, "The process pip must not keep the 24-point icon gutter")
precondition(doneSummary.icon.frame.minX == 0, "The process pip must sit on the text leading edge")
precondition(doneSummary.icon.frame.width == 8, "The process pip slot must match the 6-point dot")
precondition(abs(doneSummary.icon.frame.midY - doneSummary.label.frame.midY) <= 0.5,
  "The process pip must sit on the text baseline")
precondition(doneSummary.label.frame.minX == 12, "Process text must follow the pip without extra padding")

let wrappedSummary = ChatCell(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
window.addSubview(wrappedSummary)
wrappedSummary.configure(
  summaryRow(running: false, attention: false),
  text: NSAttributedString(
    string: "思考过程 · 调用了 2 个命令 · 阅读了 2 个文件 · 编辑了 2 个文件 · 进行了 1 次搜索",
    attributes: [.font: UIFont.systemFont(ofSize: 13)]
  )
)
wrappedSummary.layoutIfNeeded()
let wrappedLines = wrappedSummary.label.lineAdvances(width: wrappedSummary.label.bounds.width)
precondition(wrappedLines.count > 1, "The wrapped process title fixture must occupy more than one line")
let firstLineCenter = wrappedSummary.label.frame.minY + wrappedLines[0] / 2
precondition(
  abs(wrappedSummary.icon.frame.midY - firstLineCenter) <= 0.5,
  "The process pip must sit on the first line of wrapped text"
)
precondition(
  abs(wrappedSummary.icon.frame.midY - wrappedSummary.label.frame.midY) > 0.5,
  "The process pip must not center on the whole wrapped block"
)
print("Chat render: process status pip uses running, done and attention colors")

func glyphWidth(_ font: UIFont, _ text: String) -> CGFloat {
  (text as NSString).size(withAttributes: [.font: font]).width
}

let durationFont = ChatCell.messageFont(for: durationRow, compatibleWith: traits)
let summaryFont = ChatCell.messageFont(for: doneSummary.row!, compatibleWith: traits)
let userFont = ChatCell.messageFont(
  for: ChatRow(id: "user", entryID: "user", kind: "user", text: "hi"),
  compatibleWith: traits
)
precondition(glyphWidth(durationFont, "1") == glyphWidth(durationFont, "8"),
  "Duration digits must keep a fixed width")
precondition(glyphWidth(durationFont, "0") == glyphWidth(durationFont, "8"),
  "Duration digits must keep a fixed width")
precondition(glyphWidth(summaryFont, "1") == glyphWidth(summaryFont, "8"),
  "Process-count digits must keep a fixed width")
precondition(glyphWidth(userFont, "1") < glyphWidth(userFont, "8"),
  "User messages keep proportional digits")
print("Chat render: duration and process counts use tabular digits")

// A long send lands at its source viewport height without discarding text.
let longBody = (1...18).map { "Line \($0): a complete message remains available after sending." }.joined(separator: "\n")
let longRow = ChatRow(id: "long:user", entryID: "long", kind: "user", text: longBody)
let longCell = ChatCell(frame: CGRect(x: 0, y: 0, width: 350, height: 164))
window.addSubview(longCell)
longCell.collapsedHeight = 140
longCell.configure(longRow, text: NSAttributedString(string: longBody, attributes: [.font: UIFont.systemFont(ofSize: 17)]))
longCell.layoutIfNeeded()
precondition(longCell.messageContent.bounds.height == 140 && longCell.label.layer.mask != nil,
  "Long messages must land in the composer viewport with a text-only fade")
precondition(longCell.label.attributedTextValue.string == longBody && longCell.expandable,
  "Folding must preserve all text for expansion and copying")
longCell.expanded = true
longCell.setNeedsLayout()
longCell.layoutIfNeeded()
precondition(longCell.messageContent.bounds.height > 140 && longCell.label.layer.mask == nil,
  "Expanding must expose the complete message and remove the fade")
precondition(longCell.messageContent.disclosure.bounds.height >= 44,
  "Expanded messages must keep an accessible collapse target")
longCell.expanded = false
let narrowBody = Array(repeating: "x", count: 20).joined(separator: "\n")
longCell.configure(ChatRow(id: "narrow:user", entryID: "narrow", kind: "user", text: narrowBody),
  text: NSAttributedString(string: narrowBody, attributes: [.font: UIFont.systemFont(ofSize: 17)]))
longCell.layoutIfNeeded()
precondition(longCell.messageContent.disclosure.bounds.width >= longCell.messageContent.disclosure.intrinsicContentSize.width,
  "A narrow multiline message must still have room for its expansion affordance")
longCell.configure(ChatRow(id: "short:user", entryID: "short", kind: "user", text: "hello"),
  text: NSAttributedString(string: "hello", attributes: [.font: UIFont.systemFont(ofSize: 17)]))
longCell.layoutIfNeeded()
precondition(longCell.messageContent.bounds.height < 68 && !longCell.expandable && longCell.label.layer.mask == nil,
  "Reusing a folded cell for a short message must restore its natural height and clear the mask")
print("Chat send: bounded landing, complete expansion, accessible collapse and short-message reuse passed")

let retryCell = ChatCell(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
retryCell.configure(ChatRow(id: "failed:pending", entryID: "failed", kind: "pending", text: "Retry", actionable: true), text: NSAttributedString(string: "Retry"))
retryCell.layoutIfNeeded()
var activatedRetry = false
retryCell.onActivate = { activatedRetry = true }
precondition(retryCell.accessibilityActivate() && activatedRetry, "Accessible status rows must invoke their retry/reconnect action")
print("Chat render: accessible status actions remain available with expandable messages")
