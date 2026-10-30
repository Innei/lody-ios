import CoreText
import SwiftUI
import UIKit

private func lineInk(_ attributed: NSAttributedString) -> CGRect {
  CTLineGetImageBounds(CTLineCreateWithAttributedString(attributed), nil)
}

private func inkBottom(text: String, font: UIFont) -> CGFloat {
  guard !text.isEmpty else { return 0 }
  let ink = lineInk(NSAttributedString(string: text, attributes: [.font: font]))
  return ceil(max(0, font.ascender - ink.origin.y))
}

@Observable
final class ChatNavigationTitleModel {
  var text = ""
}

struct ChatNavigationTitleBridge: View {
  var model: ChatNavigationTitleModel

  var body: some View {
    Text(model.text)
      .font(.headline)
      .foregroundStyle(Color.primary)
      .lineLimit(1)
      .truncationMode(.tail)
      .contentTransition(.numericText())
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}

final class ChatNavigationTitleHost: UIView {
  private let model: ChatNavigationTitleModel
  private let hosting: UIHostingController<ChatNavigationTitleBridge>
  private var probe: ChatTitleTransitionProbe?
  var onTransitionReport: ((String) -> Void)?

  var text: String { model.text }

  override init(frame: CGRect) {
    let model = ChatNavigationTitleModel()
    self.model = model
    hosting = UIHostingController(rootView: ChatNavigationTitleBridge(model: model))
    super.init(frame: frame)
    hosting.safeAreaRegions = []
    hosting.sizingOptions = []
    hosting.view.backgroundColor = .clear
    hosting.view.isOpaque = false
    hosting.view.insetsLayoutMarginsFromSafeArea = false
    hosting.view.clipsToBounds = false
    hosting.view.isUserInteractionEnabled = false
    hosting.view.isAccessibilityElement = false
    hosting.view.accessibilityElementsHidden = true
    clipsToBounds = false
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    accessibilityElementsHidden = true
    addSubview(hosting.view)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(_ text: String, animated: Bool) {
    guard text != model.text else { return }
    let update = { self.model.text = text }
    let motion = animated
      && !model.text.isEmpty
      && !text.isEmpty
      && !UIAccessibility.isReduceMotionEnabled
    if motion {
      withAnimation(.default, update)
      if LodyUIVerify.enabled { probe = ChatTitleTransitionProbe(host: self) }
    } else {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction, update)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    hosting.view.frame = bounds
  }

  override func sizeThatFits(_ size: CGSize) -> CGSize {
    hosting.sizeThatFits(
      in: CGSize(width: max(1, size.width), height: UIView.layoutFittingExpandedSize.height)
    )
  }
}

@MainActor
final class ChatTitleTransitionProbe: NSObject {
  private weak var host: ChatNavigationTitleHost?
  private var link: CADisplayLink?
  private var frames: [Data] = []
  private var detached = 0
  private let started = CACurrentMediaTime()

  init(host: ChatNavigationTitleHost) {
    self.host = host
    super.init()
    let link = CADisplayLink(target: self, selector: #selector(sample(_:)))
    self.link = link
    link.add(to: .main, forMode: .common)
  }

  @objc private func sample(_ link: CADisplayLink) {
    guard let host, link.timestamp - started < 0.7 else { finish(); return }
    if host.window == nil { detached += 1 }
    let size = CGSize(width: max(1, host.bounds.width), height: max(1, host.bounds.height))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
      host.layer.render(in: context.cgContext)
    }
    if let data = image.pngData() { frames.append(data) }
  }

  private func finish() {
    link?.invalidate(); link = nil
    guard let host, let first = frames.first, let last = frames.last else { return }
    let mid = frames.filter { $0 != first && $0 != last }.count
    host.onTransitionReport?("transition-frames:\(mid) detached:\(detached) sampled:\(frames.count)")
  }
}

final class ChatNavigationTitleButton: UIButton {
  let titleHost = ChatNavigationTitleHost()
  let captionLabel = UILabel()
  let menuGlyph = UIImageView(image: UIImage(
    systemName: "chevron.down",
    withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
  ))
  var refreshCaption: (() -> Void)?

  var displayedTitle: String { titleHost.text }

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    contentHorizontalAlignment = .leading
    titleLabel?.isHidden = true
    captionLabel.numberOfLines = 1
    captionLabel.lineBreakMode = .byTruncatingMiddle
    captionLabel.clipsToBounds = false
    captionLabel.isOpaque = false
    captionLabel.backgroundColor = .clear
    captionLabel.isUserInteractionEnabled = false
    captionLabel.isAccessibilityElement = false
    menuGlyph.tintColor = .lodyTertiary
    menuGlyph.isHidden = true
    menuGlyph.isUserInteractionEnabled = false
    addSubview(titleHost)
    addSubview(captionLabel)
    addSubview(menuGlyph)
    registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (button: ChatNavigationTitleButton, _) in
      button.refreshCaption?()
    }
    titleHost.onTransitionReport = { [weak self] report in self?.accessibilityValue = report }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var isHighlighted: Bool {
    didSet {
      let alpha: CGFloat = isHighlighted ? 0.4 : 1
      titleHost.alpha = alpha
      captionLabel.alpha = alpha
      menuGlyph.alpha = alpha
    }
  }

  override var intrinsicContentSize: CGSize {
    sizeThatFits(CGSize(width: UIView.layoutFittingExpandedSize.width, height: 44))
  }

  override func sizeThatFits(_ size: CGSize) -> CGSize {
    let titleFont = UIFont.preferredFont(forTextStyle: .headline)
    let titleWidth = (titleHost.text as NSString).size(withAttributes: [.font: titleFont]).width
    let subtitleWidth = captionLabel.attributedText?.size().width ?? 0
    let glyph: CGFloat = menuGlyph.isHidden ? 0 : Self.menuSlot
    return CGSize(width: ceil(8 + max(titleWidth + glyph, subtitleWidth)), height: 44)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let inset: CGFloat = 8
    let width = max(0, bounds.width - inset)
    let x = effectiveUserInterfaceLayoutDirection == .rightToLeft ? 0 : inset
    let titleFont = UIFont.preferredFont(forTextStyle: .headline)
    let captionFont = UIFont.preferredFont(forTextStyle: .caption1)
    let titleLine = titleHost.text.isEmpty ? 0 : ceil(titleFont.lineHeight)
    let subtitleLine = captionLabel.isHidden ? 0 : ceil(captionFont.lineHeight)
    let titleHeight = titleLine == 0 ? 0 : ceil(max(
      titleLine,
      titleHost.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingExpandedSize.height)).height
    ))
    let subtitleHeight = subtitleLine == 0 ? 0 : ceil(max(
      subtitleLine,
      captionLabel.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingExpandedSize.height)).height
    ))
    let titleInk = titleLine == 0 ? 0 : inkBottom(text: titleHost.text, font: titleFont)
    let symbolOpticalPad: CGFloat = 4
    let captionInkPad = subtitleLine == 0
      ? 0
      : max(0, round(captionFont.ascender - captionFont.capHeight) + symbolOpticalPad)
    let spacing: CGFloat = titleLine > 0 && subtitleLine > 0 ? 8 : 0
    let stackHeight = titleInk + spacing + subtitleHeight - captionInkPad
    let y = max(0, (bounds.height - stackHeight) / 2)
    let glyph: CGFloat = menuGlyph.isHidden ? 0 : Self.menuSlot
    titleHost.frame = CGRect(x: x, y: y, width: max(0, width - glyph), height: titleHeight)
    titleHost.isHidden = titleHeight == 0
    let titleWidth = ceil((titleHost.text as NSString).size(withAttributes: [.font: titleFont]).width)
    let glyphSize = menuGlyph.intrinsicContentSize
    menuGlyph.frame = CGRect(
      x: x + min(titleWidth, max(0, width - glyph)) + 4,
      y: y + (titleLine - glyphSize.height) / 2,
      width: glyphSize.width,
      height: glyphSize.height
    )
    captionLabel.frame = CGRect(
      x: x,
      y: y + titleInk + spacing - captionInkPad,
      width: width,
      height: subtitleHeight
    )
  }

  private static let menuSlot: CGFloat = 16
}

@MainActor
enum ChatNavigationTitle {
  static func plainSubtitle(project: String, branch: String, pullRequest: String = "", offline: Bool = false) -> String {
    [
      branch.isEmpty ? project : branch,
      pullRequest.isEmpty ? "" : "PR " + pullRequest,
      offline ? String(localized: "devices.offline", bundle: .lody) : "",
    ].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  static func configureButton(
    _ button: ChatNavigationTitleButton, title: String, subtitle: String, machine: String = "", branch: String = "",
    machineState: String = "", pullRequest: String = "", pullRequestFailing: Bool = false, menu: Bool = false
  ) {
    button.titleHost.apply(title, animated: true)
    button.menuGlyph.isHidden = !menu
    button.captionLabel.lineBreakMode = .byTruncatingMiddle
    let caption = { [weak button] in
      guard let button else { return }
      let attributed = attributedSubtitle(project: subtitle, branch: branch, machineState: machineState,
        pullRequest: pullRequest, failing: pullRequestFailing, traits: button.traitCollection)
      button.captionLabel.attributedText = attributed
      button.captionLabel.isHidden = attributed == nil
    }
    button.refreshCaption = caption
    caption()
    let offline = machineState == "offline" ? String(localized: "devices.offline", bundle: .lody) : ""
    let failing = pullRequestFailing ? String(localized: "session.title.checksFailed", bundle: .lody) : ""
    let pr = pullRequest.isEmpty ? "" : "PR " + pullRequest
    button.accessibilityLabel = [title, branch.isEmpty ? subtitle : branch, pr, failing, offline].filter { !$0.isEmpty }.joined(separator: ", ")
    button.sizeToFit()
    button.bounds.size.height = 44
  }

  static func pullRequestChip(_ label: String, failing: Bool, traits: UITraitCollection) -> UIImage {
    let font = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits)
    let ink = UIColor.lodyInk.resolvedColor(with: traits)
    let symbolSize = max(1, font.pointSize - 2)
    let symbol = UIImage(
      systemName: "arrow.triangle.pull",
      withConfiguration: UIImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium, scale: .small)
    )?.withTintColor(ink, renderingMode: .alwaysOriginal)
    let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: ink])
    let textSize = text.size()
    let dot: CGFloat = failing ? 6 : 0
    let height = ceil(font.lineHeight) + 2
    let width = ceil(6 + symbolSize + 3 + textSize.width + (failing ? 4 + dot : 0) + 7)
    let format = UIGraphicsImageRendererFormat(for: traits)
    format.opaque = false
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { _ in
      UIColor.lodyInset.resolvedColor(with: traits).setFill()
      UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: height / 2).fill()
      symbol?.draw(in: CGRect(x: 6, y: (height - symbolSize) / 2, width: symbolSize, height: symbolSize))
      text.draw(at: CGPoint(x: 6 + symbolSize + 3, y: (height - textSize.height) / 2))
      guard failing else { return }
      UIColor.lodyAttention.resolvedColor(with: traits).setFill()
      UIBezierPath(ovalIn: CGRect(x: width - 7 - dot, y: (height - dot) / 2, width: dot, height: dot)).fill()
    }
  }

  static func apply(title: String, subtitle: String, button: UIButton, to item: UINavigationItem) {
    clearNativeSubtitle(item)
    item.style = .browser
    let header = LodyNavigationHeader.of(item)
    header.title = title.isEmpty ? nil : title
    header.titleView = button
  }

  static func preserveSubtitle(_ subtitle: String, on item: UINavigationItem) {
    item.subtitle = subtitle.isEmpty ? nil : subtitle
  }

  static func clearNativeSubtitle(_ item: UINavigationItem) {
    item.subtitle = nil
  }

  static func setDisappearing(_ disappearing: Bool, on item: UINavigationItem) {
    LodyNavigationHeader.of(item).suspended = disappearing
  }

  static func detach(button: UIButton, from item: UINavigationItem) {
    let header = LodyNavigationHeader.of(item)
    guard header.titleView === button else { return }
    header.title = nil
    header.titleView = nil
    if item.titleView === button {
      item.titleView = nil
    }
  }

  private static func attributedSubtitle(
    project: String, branch: String, machineState: String, pullRequest: String, failing: Bool, traits: UITraitCollection
  ) -> NSAttributedString? {
    let font = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits)
    let color = UIColor.secondaryLabel
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
    ]
    let text = NSMutableAttributedString()
    func append(_ name: String, symbol: String) {
      guard !name.isEmpty else { return }
      if let attachment = symbolAttachment(symbol, font: font, color: color) {
        text.append(NSAttributedString(attachment: attachment))
        text.append(NSAttributedString(string: " ", attributes: attributes))
      }
      text.append(NSAttributedString(string: name, attributes: attributes))
    }
    if branch.isEmpty {
      append(project, symbol: "folder")
    } else {
      append(branch, symbol: "arrow.triangle.branch")
    }
    if !pullRequest.isEmpty {
      let chip = pullRequestChip(pullRequest, failing: failing, traits: traits)
      let attachment = NSTextAttachment()
      attachment.image = chip
      attachment.bounds = CGRect(x: 0, y: (font.capHeight - chip.size.height) / 2, width: chip.size.width, height: chip.size.height)
      if text.length > 0 { text.append(NSAttributedString(string: "  ", attributes: attributes)) }
      text.append(NSAttributedString(attachment: attachment))
    }
    if machineState == "offline" {
      if text.length > 0 { text.append(NSAttributedString(string: " · ", attributes: attributes)) }
      text.append(NSAttributedString(string: String(localized: "devices.offline", bundle: .lody), attributes: attributes))
    }
    return text.length == 0 ? nil : text
  }

  private static func symbolAttachment(_ name: String, font: UIFont, color: UIColor) -> NSTextAttachment? {
    let size = max(1, font.pointSize - 3)
    let image = UIImage(
      systemName: name,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: .regular, scale: .small)
    )?.withTintColor(color, renderingMode: .alwaysOriginal)
    guard let image else { return nil }
    let drawn = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
      image.draw(in: CGRect(origin: .zero, size: CGSize(width: size, height: size)))
    }
    let attachment = NSTextAttachment()
    attachment.image = drawn
    attachment.bounds = CGRect(x: 0, y: (font.capHeight - size) / 2, width: size, height: size)
    return attachment
  }
}
