import UIKit

let menuButton = UIButton(type: .system)
var menuConfiguration = UIButton.Configuration.plain()
menuConfiguration.attributedTitle = AttributedString("我的超长工作区名称不能折行")
LodyMenuButtonStyle.apply(menuConfiguration, to: menuButton)
assert(menuButton.titleLabel?.numberOfLines == 1, "Workspace menu title must stay on one line")
assert(menuButton.titleLabel?.lineBreakMode == .byTruncatingTail, "Long workspace names must truncate at the tail")
assert(menuButton.configuration?.titleLineBreakMode == .byTruncatingTail, "The button configuration must not restore wrapping")

let letter = LodyMenuButtonStyle.avatarImage(text: "I", fill: .systemIndigo, photo: nil)
let avatarSource = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { _ in
  UIColor.red.setFill()
  UIRectFill(CGRect(x: 0, y: 0, width: 80, height: 40))
}
let loaded = LodyMenuButtonStyle.avatarImage(
  text: "I", fill: .systemIndigo, photo: LodyListPhoto.circular(avatarSource)
)
assert(letter.size.width == LodyMenuButtonStyle.avatarSide)
assert(loaded.size.width == LodyMenuButtonStyle.avatarSide)
assert(letter.pngData() != loaded.pngData(), "An account photo must replace the letter fallback")
assert(LodyMenuButtonStyle.trailingInset > 4, "The workspace name needs room after the last glyph")

var swipedState = UICellConfigurationState(traitCollection: UITraitCollection())
swipedState.isSwiped = true
swipedState.isSelected = true
swipedState.isHighlighted = true
let swipedBackgroundState = LodyListCellBackground.visualState(for: swipedState)
assert(!swipedBackgroundState.isSwiped, "Swipe actions must use the resting row background")
assert(!swipedBackgroundState.isSelected, "Swipe actions must not render the selected background")
assert(!swipedBackgroundState.isHighlighted, "Swipe actions must not render the highlighted background")

var tappedState = UICellConfigurationState(traitCollection: UITraitCollection())
tappedState.isSelected = true
tappedState.isHighlighted = true
let tappedBackgroundState = LodyListCellBackground.visualState(for: tappedState)
assert(tappedBackgroundState.isSelected, "Normal row selection must stay visible")
assert(tappedBackgroundState.isHighlighted, "Normal tap highlighting must stay visible")

assert(LodyListPhoto.url("person.crop.circle") == nil)
assert(LodyListPhoto.url("https://avatars.githubusercontent.com/u/1")?.scheme == "https")
assert(LodyListPhoto.url("http://avatars.githubusercontent.com/u/1") == nil)
assert(LodyListPhoto.url("javascript:alert(1)") == nil)
assert(LodyListPhoto.url("https://user:pass@example.com/a.png") == nil)
assert(LodyListPhoto.url("data:image/png;base64,aa")?.scheme == "data")
assert(LodyListPhoto.url("file:///tmp/a.png")?.isFileURL == true)

let source = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 40)).image { _ in
  UIColor.red.setFill()
  UIRectFill(CGRect(x: 0, y: 0, width: 80, height: 40))
}
let photo = LodyListPhoto.circular(source)
assert(photo.size == LodyListPhoto.size)
assert(photo.renderingMode == .alwaysOriginal)

func alpha(_ image: UIImage, x: CGFloat, y: CGFloat) -> CGFloat {
  var pixel: [UInt8] = [0, 0, 0, 0]
  let space = CGColorSpaceCreateDeviceRGB()
  let context = CGContext(
    data: &pixel,
    width: 1,
    height: 1,
    bitsPerComponent: 8,
    bytesPerRow: 4,
    space: space,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.translateBy(x: -x, y: -y)
  context.draw(image.cgImage!, in: CGRect(origin: .zero, size: image.size))
  return CGFloat(pixel[3]) / 255
}

assert(alpha(photo, x: 0, y: 0) < 0.05, "Photo corners must be transparent")
assert(alpha(photo, x: photo.size.width - 1, y: 0) < 0.05, "Photo corners must be transparent")
assert(alpha(photo, x: photo.size.width / 2, y: photo.size.height / 2) > 0.9, "Photo center must stay opaque")

let disk = FileManager.default.temporaryDirectory.appendingPathComponent("lody-list-photo.png")
try! source.pngData()!.write(to: disk)
let fromFile = LodyListPhoto.image(for: disk, ready: { _ in })
assert(fromFile != nil, "file URLs must decode a circular photo")
assert(fromFile!.renderingMode == .alwaysOriginal)
assert(alpha(fromFile!, x: 0, y: 0) < 0.05)

let dataURL = URL(string: "data:image/png;base64," + source.pngData()!.base64EncodedString())!
let fromData = LodyListPhoto.image(for: dataURL, ready: { _ in })
assert(fromData != nil, "data image URLs must decode a circular photo")

print("PASS: workspace title stays single-line, swiped rows stay unselected, and list photos are safely cropped")

let restingState = UICellConfigurationState(traitCollection: UITraitCollection())
assert(LodyListCellBackground.outlineConfiguration(for: restingState).backgroundColor == .clear, "Outline rows at rest must show the section card, not their own background")
assert(LodyListCellBackground.outlineConfiguration(for: tappedState).backgroundColor != .clear, "Outline rows must still paint their highlight")
assert(LodyListCellBackground.outlineConfiguration(for: swipedState).backgroundColor != .clear, "A swiped outline row must carry an opaque background with it")
assert(LodySectionCardView(frame: .zero).layer.cornerRadius > 0, "The section card must be rounded")

struct LodyListRow {
  var title = ""
  var subtitle = ""
  var modelName = ""
  var value = ""
  var unread = false
  var destructive = false
  var badge = ""
  var subtitleMono = false
  var pinned = false
  var diff: [String: Int] = [:]
  var monogram = ""
  var imageTint = ""
}

// Layout-only harness: project status colors are outside this check.
func lodyTint(_ value: String) -> UIColor? {
  precondition(value.isEmpty)
  return nil
}

func laidOutSessionRow(_ content: LodySessionRowContent) -> LodySessionRowView {
  let view = LodySessionRowView(content)
  let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
  window.makeKeyAndVisible()
  let host = UIView(frame: window.bounds)
  window.addSubview(host)
  host.addSubview(view)
  view.translatesAutoresizingMaskIntoConstraints = false
  NSLayoutConstraint.activate([
    view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
    view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
    view.topAnchor.constraint(equalTo: host.topAnchor),
  ])
  host.layoutIfNeeded()
  withExtendedLifetime(window) {}
  return view
}

func sessionMark(in view: UIView) -> UIView {
  view.subviews.first { $0.layer.cornerRadius == 7 }!
}

func labels(in view: UIView) -> [UILabel] {
  [view as? UILabel].compactMap { $0 } + view.subviews.flatMap(labels(in:))
}

func sessionLabel(_ view: UIView, _ text: String) -> UILabel {
  labels(in: view).first { ($0.text ?? $0.attributedText?.string) == text }!
}

func midY(_ inner: UIView, in outer: UIView) -> CGFloat {
  inner.convert(CGPoint(x: 0, y: inner.bounds.midY), to: outer).y
}

let live = laidOutSessionRow(
  LodySessionRowContent(
    row: LodyListRow(title: "正在运行的任务", subtitle: "lody-ios", value: "刚刚"),
    dot: .systemBlue,
    live: true
  )
)
let liveMark = sessionMark(in: live)
let liveTitle = sessionLabel(live, "正在运行的任务")
let liveMeta = sessionLabel(live, "lody-ios")
let liveMarkY = midY(liveMark, in: live)
let liveTitleY = liveTitle.convert(CGPoint(x: 0, y: liveTitle.font.ascender / 2), to: live).y
let liveMetaY = midY(liveMeta, in: live)
assert(
  abs(liveMarkY - liveTitleY) < abs(liveMarkY - liveMetaY),
  "Live mark must sit on the title, not the project name"
)
assert(
  liveMark.convert(CGPoint(x: liveMark.bounds.maxX, y: 0), to: live).x
    <= liveTitle.convert(.zero, to: live).x + 1,
  "Live mark must sit in front of the title"
)

let solo = laidOutSessionRow(
  LodySessionRowContent(
    row: LodyListRow(title: "无项目会话", value: "刚刚"),
    dot: .systemBlue,
    live: true
  )
)
let soloMark = sessionMark(in: solo)
let soloTitle = sessionLabel(solo, "无项目会话")
assert(
  abs(midY(soloMark, in: solo) - soloTitle.convert(CGPoint(x: 0, y: soloTitle.font.ascender / 2), to: solo).y) < 6,
  "A row without a project name still keeps the mark on the title"
)

print("PASS: session live mark sits in front of the title")

func frame(_ inner: UIView, in outer: UIView) -> CGRect {
  inner.convert(inner.bounds, to: outer)
}

let badgeOnly = laidOutSessionRow(
  LodySessionRowContent(
    row: LodyListRow(title: "Conversation opening greeting", value: "Yesterday", badge: "Archived"),
    dot: nil,
    live: false
  )
)
let withProject = laidOutSessionRow(
  LodySessionRowContent(
    row: LodyListRow(title: "hihi", subtitle: "lody-ios", value: "Yesterday", badge: "Archived"),
    dot: nil,
    live: false
  )
)
let badge = sessionLabel(badgeOnly, "Archived")
let badgeTitle = sessionLabel(badgeOnly, "Conversation opening greeting")
let badgeTime = sessionLabel(badgeOnly, "Yesterday")
let badgeFrame = frame(badge, in: badgeOnly)
let badgeTitleFrame = frame(badgeTitle, in: badgeOnly)
assert(
  badgeFrame.maxY <= badgeTitleFrame.minY + 1,
  "A badge with no project name must keep its own line above the title"
)
assert(
  abs(badgeFrame.minX - badgeTitleFrame.minX) < 2,
  "A leading badge must line up with the title, not sit on an empty meta label"
)
assert(
  abs(midY(badgeTime, in: badgeOnly) - midY(badge, in: badgeOnly))
    < abs(midY(badgeTime, in: badgeOnly) - midY(badgeTitle, in: badgeOnly)),
  "Time stays on the badge line when the session has no project name"
)
assert(
  abs(badgeOnly.bounds.height - withProject.bounds.height) < 8,
  "A chat row with only a badge keeps the two-line session height"
)

print("PASS: a badge without a project name keeps the two-line session row")

// Compare the same real content view at the same width, including reuse back
// into the default host. Sidebar typography can shrink, but not text or touch targets.
@MainActor func fittedHeight(_ view: UIView) -> CGFloat {
  view.systemLayoutSizeFitting(
    CGSize(width: 288, height: 0),
    withHorizontalFittingPriority: .required,
    verticalFittingPriority: .fittingSizeLevel
  ).height
}

let densityRow = LodyListRow(title: "Review sidebar", subtitle: "feature/sidebar", modelName: "GPT-6", value: "Now")
let sessionContent = LodySessionRowContent(row: densityRow, dot: .systemBlue, live: true)
let densitySession = LodySessionRowView(sessionContent)
let groupedSessionHeight = fittedHeight(densitySession)
let groupedSessionLabel = densitySession.accessibilityLabel
let groupedTitleFont = sessionLabel(densitySession, densityRow.title).font!
var sidebarSession = sessionContent
sidebarSession.density = .compact
densitySession.configuration = sidebarSession
assert(fittedHeight(densitySession) <= groupedSessionHeight - 8, "Sidebar must fit more rows at the same width")
assert(fittedHeight(densitySession) >= 44, "Compact rows must keep a 44 pt touch target")
assert(densitySession.accessibilityLabel == groupedSessionLabel, "Sidebar must retain all session information")
assert(sessionLabel(densitySession, densityRow.title).font.pointSize < groupedTitleFont.pointSize, "Sidebar title must be quieter than the grouped title")
assert(sessionLabel(densitySession, densityRow.title).adjustsFontForContentSizeCategory)
let groupedMetaFont = LodySessionRowView.meta(for: densityRow).attribute(.font, at: 0, effectiveRange: nil) as! UIFont
let sidebarMetaFont = sessionLabel(densitySession, densityRow.subtitle).attributedText!.attribute(.font, at: 0, effectiveRange: nil) as! UIFont
assert(sidebarMetaFont.pointSize < groupedMetaFont.pointSize, "Attributed branch text must follow sidebar density too")
densitySession.configuration = sessionContent
assert(sessionLabel(densitySession, densityRow.title).font == groupedTitleFont, "Reuse must restore the phone title size")
assert(abs(fittedHeight(densitySession) - groupedSessionHeight) < 0.5, "Reuse must restore grouped row spacing")
sidebarSession.row = LodyListRow(title: "No metadata")
densitySession.configuration = sidebarSession
assert(fittedHeight(densitySession) >= 44, "A one-line sidebar row must still be tappable")

let projectContent = LodyProjectRowContent(row: LodyListRow(title: "Lody", subtitle: "/tmp/lody", monogram: "L"), accent: .systemBlue)
let densityProject = LodyProjectRowView(projectContent)
let groupedProjectHeight = fittedHeight(densityProject)
let groupedProjectLabel = densityProject.accessibilityLabel
let projectText = densityProject.subviews.first { $0 is UIStackView }!
let groupedProjectFont = sessionLabel(projectText, "Lody").font!
var sidebarProject = projectContent
sidebarProject.density = .compact
densityProject.configuration = sidebarProject
assert(fittedHeight(densityProject) <= groupedProjectHeight - 8)
assert(fittedHeight(densityProject) >= 44)
assert(densityProject.accessibilityLabel == groupedProjectLabel)
assert(sessionLabel(projectText, "Lody").font.pointSize < groupedProjectFont.pointSize)
densityProject.configuration = projectContent
assert(sessionLabel(projectText, "Lody").font == groupedProjectFont, "Reuse must restore the phone project size")
assert(abs(fittedHeight(densityProject) - groupedProjectHeight) < 0.5)
print("PASS: sidebar uses quieter typography with complete text and 44 pt targets; grouped reuse restores its font and spacing")

assert(
  LodyListSectionAnimation.itemCountsCrossEmpty(previous: ["settings": 0], next: ["settings": 3]),
  "Filling an empty section must skip the footer interpolation"
)
assert(
  LodyListSectionAnimation.itemCountsCrossEmpty(previous: ["settings": 3], next: ["settings": 0]),
  "Clearing a section must skip the footer interpolation"
)
assert(
  !LodyListSectionAnimation.itemCountsCrossEmpty(previous: ["settings": 3], next: ["settings": 4]),
  "Growing a populated section can keep its row animation"
)
assert(
  !LodyListSectionAnimation.itemCountsCrossEmpty(previous: ["help": 0], next: ["help": 0]),
  "A footer-only section that stays empty is not a crossing"
)
assert(
  !LodyListSectionAnimation.itemCountsCrossEmpty(previous: ["a": 2], next: ["a": 2, "b": 3]),
  "A newly inserted populated section never parked a footer at the top"
)
assert(
  LodyListSectionAnimation.hidesEmptyFooter(rowCount: 0, placeholder: "Loading remote settings…"),
  "An empty section with a placeholder must not park its description at the top"
)
assert(
  !LodyListSectionAnimation.hidesEmptyFooter(rowCount: 3, placeholder: "Loading remote settings…"),
  "A populated section keeps its footer under the card"
)
assert(
  !LodyListSectionAnimation.hidesEmptyFooter(rowCount: 0, placeholder: ""),
  "A footer-only help section stays visible when the host has no placeholder"
)
print("PASS: empty-to-populated list sections skip the footer interpolation")
