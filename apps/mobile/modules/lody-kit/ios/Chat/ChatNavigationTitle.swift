import SwiftUI
import UIKit

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
      && window != nil
      && !text.isEmpty
      && !UIAccessibility.isReduceMotionEnabled
    if motion {
      withAnimation(.default, update)
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

final class ChatNavigationTitleButton: UIButton {
  let titleHost = ChatNavigationTitleHost()
  let captionLabel = UILabel()

  var displayedTitle: String { titleHost.text }

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    contentHorizontalAlignment = .leading
    titleLabel?.isHidden = true
    captionLabel.numberOfLines = 1
    captionLabel.lineBreakMode = .byTruncatingMiddle
    captionLabel.clipsToBounds = false
    captionLabel.isUserInteractionEnabled = false
    captionLabel.isAccessibilityElement = false
    addSubview(titleHost)
    addSubview(captionLabel)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var isHighlighted: Bool {
    didSet {
      let alpha: CGFloat = isHighlighted ? 0.4 : 1
      titleHost.alpha = alpha
      captionLabel.alpha = alpha
    }
  }

  override var intrinsicContentSize: CGSize {
    sizeThatFits(CGSize(width: UIView.layoutFittingExpandedSize.width, height: 44))
  }

  override func sizeThatFits(_ size: CGSize) -> CGSize {
    let titleFont = UIFont.preferredFont(forTextStyle: .headline)
    let titleWidth = (titleHost.text as NSString).size(withAttributes: [.font: titleFont]).width
    let subtitleWidth = captionLabel.attributedText?.size().width ?? 0
    return CGSize(width: ceil(8 + max(titleWidth, subtitleWidth)), height: 44)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let inset: CGFloat = 8
    let width = max(0, bounds.width - inset)
    let x = effectiveUserInterfaceLayoutDirection == .rightToLeft ? 0 : inset
    let titleFont = UIFont.preferredFont(forTextStyle: .headline)
    let captionFont = UIFont.preferredFont(forTextStyle: .caption1)
    let titleHeight = titleHost.text.isEmpty ? 0 : ceil(max(
      titleFont.lineHeight,
      titleHost.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingExpandedSize.height)).height
    )) + 2
    let subtitleHeight = captionLabel.isHidden ? 0 : ceil(max(
      captionFont.lineHeight,
      captionLabel.sizeThatFits(CGSize(width: width, height: UIView.layoutFittingExpandedSize.height)).height
    )) + 2
    let spacing: CGFloat = titleHeight > 0 && subtitleHeight > 0 ? 1 : 0
    let y = max(0, (bounds.height - titleHeight - spacing - subtitleHeight) / 2)
    titleHost.frame = CGRect(x: x, y: y, width: width, height: titleHeight)
    titleHost.isHidden = titleHeight == 0
    captionLabel.frame = CGRect(x: x, y: y + titleHeight + spacing, width: width, height: subtitleHeight)
  }
}

@MainActor
enum ChatNavigationTitle {
  static func plainSubtitle(project: String, machine: String) -> String {
    [project, machine].filter { !$0.isEmpty }.joined(separator: " · ")
  }

  static func configureButton(_ button: ChatNavigationTitleButton, title: String, subtitle: String, machine: String = "") {
    button.titleHost.apply(title, animated: true)
    if let attributed = attributedSubtitle(project: subtitle, machine: machine) {
      button.captionLabel.attributedText = NSAttributedString(attributed)
      button.captionLabel.isHidden = false
    } else {
      button.captionLabel.attributedText = nil
      button.captionLabel.isHidden = true
    }
    button.accessibilityLabel = [title, subtitle, machine].filter { !$0.isEmpty }.joined(separator: ", ")
    button.sizeToFit()
    button.bounds.size.height = 44
  }

  static func apply(title: String, subtitle: String, button: UIButton, to item: UINavigationItem) {
    clearNativeSubtitle(item)
    item.style = .browser
    if item.titleView !== button {
      item.titleView = button
    }
  }

  static func preserveSubtitle(_ subtitle: String, on item: UINavigationItem) {
    item.subtitle = subtitle.isEmpty ? nil : subtitle
  }

  static func clearNativeSubtitle(_ item: UINavigationItem) {
    item.subtitle = nil
  }

  static func detach(button: UIButton, from item: UINavigationItem) {
    if item.titleView === button {
      item.titleView = nil
    }
  }

  private static func attributedSubtitle(project: String, machine: String) -> AttributedString? {
    let font = UIFont.preferredFont(forTextStyle: .caption1)
    let color = UIColor.secondaryLabel
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
    ]
    let text = NSMutableAttributedString()
    func append(_ name: String, symbol: String) {
      guard !name.isEmpty else { return }
      if text.length > 0 {
        text.append(NSAttributedString(string: " · ", attributes: attributes))
      }
      if let attachment = symbolAttachment(symbol, font: font, color: color) {
        text.append(NSAttributedString(attachment: attachment))
        text.append(NSAttributedString(string: " ", attributes: attributes))
      }
      text.append(NSAttributedString(string: name, attributes: attributes))
    }
    append(project, symbol: "folder")
    append(machine, symbol: "desktopcomputer")
    return text.length == 0 ? nil : AttributedString(text)
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
