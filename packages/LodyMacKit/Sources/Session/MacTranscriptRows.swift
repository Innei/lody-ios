import AppKit
import LodyData

@MainActor
final class MacUserTurnView: NSView {
  init(text: String) {
    super.init(frame: .zero)
    let bubble = MacFillView(fill: .quaternarySystemFill, radius: 12)
    let label = NSTextField(wrappingLabelWithString: text)
    label.isSelectable = true
    label.font = .systemFont(ofSize: 13)
    label.translatesAutoresizingMaskIntoConstraints = false
    bubble.addSubview(label)
    bubble.translatesAutoresizingMaskIntoConstraints = false
    addSubview(bubble)
    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
      label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
      label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
      label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12),
      bubble.topAnchor.constraint(equalTo: topAnchor),
      bubble.bottomAnchor.constraint(equalTo: bottomAnchor),
      bubble.trailingAnchor.constraint(equalTo: trailingAnchor),
      bubble.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 80),
      bubble.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.78),
    ])
    setAccessibilityIdentifier("transcript-user")
  }

  required init?(coder: NSCoder) { nil }
}

@MainActor
final class MacActivityLine: NSStackView {
  init(symbol: String, text: String, attention: Bool, running: Bool, diff: Bool = false) {
    super.init(frame: .zero)
    let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
    icon.symbolConfiguration = .init(pointSize: 11, weight: .regular)
    icon.contentTintColor = attention ? .systemOrange : .tertiaryLabelColor
    let label = NSTextField(labelWithString: "")
    label.font = .systemFont(ofSize: 12)
    label.lineBreakMode = .byTruncatingTail
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    if diff {
      label.attributedStringValue = Self.diff(text)
    } else {
      label.stringValue = text
      label.textColor = attention ? .labelColor : .secondaryLabelColor
    }
    var views: [NSView] = [icon, label]
    if running {
      let spinner = NSProgressIndicator()
      spinner.style = .spinning
      spinner.controlSize = .mini
      spinner.startAnimation(nil)
      views.append(spinner)
    }
    setViews(views, in: .leading)
    spacing = 6
    setAccessibilityIdentifier("transcript-activity")
  }

  required init?(coder: NSCoder) { nil }

  private static func diff(_ text: String) -> NSAttributedString {
    let result = NSMutableAttributedString(string: text, attributes: [
      .foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 12),
    ])
    let source = text as NSString
    for (pattern, color) in [("\\+\\d+", NSColor.systemGreen), ("[-\u{2212}]\\d+", NSColor.systemRed)] {
      let regex = try? NSRegularExpression(pattern: pattern)
      for match in regex?.matches(in: text, range: NSRange(location: 0, length: source.length)) ?? [] {
        result.addAttribute(.foregroundColor, value: color, range: match.range)
      }
    }
    return result
  }
}

@MainActor
final class MacPermissionCard: NSView {
  var onAnswer: ((String) -> Void)?
  private var options: [SessionPermission.Option] = []

  init(permission: SessionPermission) {
    super.init(frame: .zero)
    let fill = MacFillView(fill: .controlBackgroundColor, radius: 12, border: true)
    let heading = NSTextField(labelWithString: String(localized: "mac.permission.title", bundle: .lodyMac))
    heading.font = .systemFont(ofSize: 13, weight: .semibold)
    let detail = NSTextField(wrappingLabelWithString: [permission.title, permission.path].compactMap { $0 }.joined(separator: "\n"))
    detail.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    detail.textColor = .secondaryLabelColor
    options = permission.options ?? []
    let buttons = options.enumerated().map { index, option in
      let button = NSButton(title: option.name, target: self, action: #selector(pressed(_:)))
      button.tag = index
      button.controlSize = .large
      if option.kind?.hasPrefix("allow") == true, !options.prefix(index).contains(where: { $0.kind?.hasPrefix("allow") == true }) {
        button.keyEquivalent = "\r"
        button.bezelColor = .controlAccentColor
      }
      return button
    }
    let row = NSStackView(views: buttons.reversed())
    row.spacing = 8
    let stack = NSStackView(views: [heading, detail, row])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
    stack.translatesAutoresizingMaskIntoConstraints = false
    fill.translatesAutoresizingMaskIntoConstraints = false
    fill.addSubview(stack)
    addSubview(fill)
    NSLayoutConstraint.activate([
      fill.topAnchor.constraint(equalTo: topAnchor),
      fill.bottomAnchor.constraint(equalTo: bottomAnchor),
      fill.leadingAnchor.constraint(equalTo: leadingAnchor),
      fill.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.topAnchor.constraint(equalTo: fill.topAnchor),
      stack.bottomAnchor.constraint(equalTo: fill.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: fill.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: fill.trailingAnchor),
    ])
    setAccessibilityIdentifier("permission-card")
  }

  required init?(coder: NSCoder) { nil }

  @objc private func pressed(_ sender: NSButton) {
    guard options.indices.contains(sender.tag) else { return }
    onAnswer?(options[sender.tag].optionId)
  }
}

@MainActor
final class MacFillView: NSView {
  private let fill: NSColor
  private let border: Bool

  init(fill: NSColor, radius: CGFloat, border: Bool = false) {
    self.fill = fill
    self.border = border
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = radius
    layer?.cornerCurve = .continuous
  }

  required init?(coder: NSCoder) { nil }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    layer?.backgroundColor = fill.cgColor
    layer?.borderWidth = border ? 1 : 0
    layer?.borderColor = NSColor.separatorColor.cgColor
  }
}
