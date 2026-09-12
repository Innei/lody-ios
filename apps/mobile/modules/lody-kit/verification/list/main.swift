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

func sessionLabel(_ view: UIView, _ text: String) -> UILabel {
  view.subviews.compactMap { $0 as? UILabel }.first {
    ($0.text ?? $0.attributedText?.string) == text
  }!
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

let named = laidOutSessionRow(
  LodySessionRowContent(
    row: LodyListRow(title: "Review", subtitle: "lody-ios", modelName: "GPT-6", value: "Now"),
    dot: .systemBlue,
    live: false
  )
)
assert(
  named.accessibilityLabel.contains("GPT-6"),
  "Session rows must speak the last model"
)
print("PASS: session rows expose the last model")
