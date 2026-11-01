import AppKit
import LodyData

@MainActor
final class MacUserTurnView: NSView {
  init(text: String, size: Double = MacReading.standard.textSize) {
    super.init(frame: .zero)
    let bubble = MacFillView(fill: .quaternarySystemFill, radius: 12)
    let label = NSTextField(wrappingLabelWithString: text)
    label.isSelectable = true
    label.font = .systemFont(ofSize: size)
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
      bubble.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
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
  var onQuestion: ((MacQuestionAction) -> Void)?
  private let stack = NSStackView()
  private var options: [SessionPermission.Option] = []
  private var rendered: MacPermissionFlow.Card?
  private var question: MacQuestionView?
  private let error = NSTextField(wrappingLabelWithString: "")
  private var rows: [NSButton] = []

  init(card: MacPermissionFlow.Card) {
    super.init(frame: .zero)
    let glass = NSGlassEffectView()
    glass.style = .regular
    glass.cornerRadius = 20
    if #available(macOS 27, *) { glass.effectIsInteractive = true }
    glass.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    stack.setHuggingPriority(.init(1), for: .horizontal)
    glass.contentView = stack
    addSubview(glass)
    NSLayoutConstraint.activate([
      glass.topAnchor.constraint(equalTo: topAnchor), glass.bottomAnchor.constraint(equalTo: bottomAnchor),
      glass.leadingAnchor.constraint(equalTo: leadingAnchor), glass.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
    error.textColor = .systemOrange
    error.setAccessibilityIdentifier("permission-error")
    setAccessibilityIdentifier("composer-interruption")
    update(card)
  }
  required init?(coder: NSCoder) { nil }
  override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: stack.fittingSize.height) }

  func update(_ card: MacPermissionFlow.Card) {
    if rendered?.permission != card.permission || options != card.options {
      stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
      options = card.options
      rows = []
      question = nil
      let questions = card.questions != nil
      let padding: CGFloat = questions ? 16 : 12
      stack.spacing = questions ? 12 : 8
      stack.edgeInsets = NSEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
      if card.questions != nil {
        let view = MacQuestionView()
        view.onAction = { [weak self] in self?.onQuestion?($0) }
        add(view)
        question = view
      } else {
        let icon = NSImageView(image: NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        let status = NSTextField(labelWithString: String(localized: "permission.title", bundle: .lodyData))
        status.font = .preferredFont(forTextStyle: .subheadline)
        status.textColor = .secondaryLabelColor
        let header = NSStackView(views: [icon, status, NSView()])
        header.spacing = 8
        add(header)
        let heading = NSTextField(wrappingLabelWithString: card.permission.title ?? String(localized: "mac.permission.title", bundle: .lodyMac))
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        add(heading)
        if let path = card.permission.path, !path.isEmpty {
          let detail = NSTextField(wrappingLabelWithString: path)
          detail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
          detail.textColor = .secondaryLabelColor
          add(detail)
        }
        let choices = NSStackView()
        choices.orientation = .vertical
        choices.spacing = 0
        for (index, option) in options.enumerated() {
          let row = MacActionButton(title: option.name) { [weak self] in
            guard let self, let current = rendered, current.permission == card.permission, current.ready, !current.busy else { return }
            onAnswer?(option.optionId)
          }
          row.isBordered = false
          row.alignment = .left
          row.font = .preferredFont(forTextStyle: .body)
          row.contentTintColor = option.kind?.hasPrefix("reject") == true ? .systemRed : .lodyAccent
          row.setAccessibilityIdentifier("permission-option-\(index)")
          row.setAccessibilityLabel(option.name)
          choices.addArrangedSubview(row)
          row.widthAnchor.constraint(equalTo: choices.widthAnchor).isActive = true
          row.heightAnchor.constraint(equalToConstant: 44).isActive = true
          rows.append(row)
          if index < options.count - 1 {
            let line = NSBox(); line.boxType = .separator
            choices.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: choices.widthAnchor).isActive = true
          }
        }
        add(choices)
      }
      add(error)
    }
    rendered = card
    refreshChoices()
    let enabled = card.ready && !card.busy
    if let draft = card.questions {
      let reject = options.first { $0.kind?.hasPrefix("reject") == true }
      question?.rejectTitle = reject?.name ?? ""
      question?.onReject = { [weak self] in if let reject { self?.onAnswer?(reject.optionId) } }
      question?.update(draft, enabled: enabled, canSubmit: options.contains { $0.kind?.hasPrefix("allow") == true })
    }
    error.stringValue = card.error
    error.isHidden = card.error.isEmpty
    invalidateIntrinsicContentSize()
  }
  private func add(_ child: NSView) { stack.addArrangedSubview(child); child.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -stack.edgeInsets.left-stack.edgeInsets.right).isActive = true }
  private func refreshChoices() {
    let enabled = rendered?.ready == true && rendered?.busy == false
    rows.forEach { $0.isEnabled = enabled }
  }
}

@MainActor
final class MacSubagentCard: NSView {
  init(title: String, detail: String, running: Bool) {
    super.init(frame: .zero)
    let fill = MacFillView(fill: .controlBackgroundColor, radius: 10, border: true)
    let glyph = NSImageView(image: NSImage(systemSymbolName: "person.2", accessibilityDescription: nil) ?? NSImage())
    glyph.contentTintColor = running ? .lodyAccent : .secondaryLabelColor
    let heading = NSTextField(labelWithString: title)
    heading.font = .systemFont(ofSize: 13, weight: .medium)
    heading.lineBreakMode = .byTruncatingTail
    let body = NSTextField(wrappingLabelWithString: detail)
    body.font = .systemFont(ofSize: 12)
    body.textColor = .secondaryLabelColor
    body.isHidden = detail.isEmpty
    let text = NSStackView(views: [heading, body])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 2
    let stack = NSStackView(views: [glyph, text])
    stack.alignment = .top
    stack.spacing = 8
    stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
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
    setAccessibilityElement(true)
    setAccessibilityLabel([title, detail].filter { !$0.isEmpty }.joined(separator: ", "))
    setAccessibilityIdentifier("transcript-subagent")
  }

  required init?(coder: NSCoder) { nil }
}

@MainActor
final class MacFailedSendView: NSView {
  var onRetry: (() -> Void)?

  init(text: String) {
    super.init(frame: .zero)
    let glyph = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil) ?? NSImage())
    glyph.contentTintColor = .systemOrange
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 12)
    label.textColor = .secondaryLabelColor
    let retry = NSButton(title: String(localized: "mac.transcript.retry", bundle: .lodyMac), target: nil, action: nil)
    retry.controlSize = .small
    retry.target = self
    retry.action = #selector(retryPressed)
    retry.setAccessibilityIdentifier("transcript-retry")
    let stack = NSStackView(views: [glyph, label, retry])
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
    ])
    setAccessibilityIdentifier("transcript-failed-send")
  }

  required init?(coder: NSCoder) { nil }

  @objc private func retryPressed() { onRetry?() }
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
