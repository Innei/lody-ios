import AppKit
import LodyData
import MarkdownView

@MainActor
final class MacTranscriptView: NSView {
  private let scroll = NSScrollView()
  private let column = NSStackView()
  private var rendered: [MacTranscriptItem] = []
  var onAnswer: ((String) -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    column.orientation = .vertical
    column.alignment = .leading
    column.spacing = 14
    column.edgeInsets = NSEdgeInsets(top: 20, left: 16, bottom: 20, right: 16)
    column.translatesAutoresizingMaskIntoConstraints = false
    column.setAccessibilityIdentifier("transcript")
    let document = MacFlippedView()
    document.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(column)
    scroll.documentView = document
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    addSubview(scroll)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: topAnchor),
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
      document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
      column.topAnchor.constraint(equalTo: document.topAnchor),
      column.bottomAnchor.constraint(equalTo: document.bottomAnchor),
      column.centerXAnchor.constraint(equalTo: document.centerXAnchor),
      column.widthAnchor.constraint(lessThanOrEqualToConstant: 780),
      column.widthAnchor.constraint(equalTo: document.widthAnchor).withPriority(.defaultHigh),
    ])
  }

  required init?(coder: NSCoder) { nil }

  func render(_ model: MacTranscriptModel) {
    let pinnedToBottom = isScrolledToBottom
    let items = model.items
    if items != rendered {
      rendered = items
      column.arrangedSubviews.forEach { $0.removeFromSuperview() }
      for item in items { add(view(for: item)) }
    }
    column.arrangedSubviews.filter { $0 is MacPermissionCard }.forEach { $0.removeFromSuperview() }
    if let permission = model.permission {
      let card = MacPermissionCard(permission: permission)
      card.onAnswer = { [weak self] in self?.onAnswer?($0) }
      add(card)
    }
    if pinnedToBottom { scrollToBottom() }
  }

  private var isScrolledToBottom: Bool {
    guard let document = scroll.documentView else { return true }
    return scroll.contentView.bounds.maxY >= document.frame.height - 24
  }

  private func scrollToBottom() {
    layoutSubtreeIfNeeded()
    guard let document = scroll.documentView else { return }
    scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - scroll.contentView.bounds.height)))
    scroll.reflectScrolledClipView(scroll.contentView)
  }

  private func add(_ view: NSView) {
    column.addArrangedSubview(view)
    view.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -32).isActive = true
  }

  private func view(for item: MacTranscriptItem) -> NSView {
    switch item {
    case .user(_, let text): return MacUserTurnView(text: text)
    case .prose(_, let markdown): return MacMarkdownView(markdown: markdown)
    case .plan(_, let markdown): return MacPlanView(markdown: markdown)
    case .activity(_, let symbol, let text, let attention, let running):
      return MacActivityLine(symbol: symbol, text: text, attention: attention, running: running)
    case .changes(_, let text): return MacActivityLine(symbol: "plusminus", text: text, attention: false, running: false, diff: true)
    case .notice(_, let text):
      let label = NSTextField(wrappingLabelWithString: text)
      label.textColor = .systemRed
      return label
    }
  }
}

final class MacFlippedView: NSView {
  override var isFlipped: Bool { true }
}

extension NSLayoutConstraint {
  func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
    self.priority = priority
    return self
  }
}

@MainActor
final class MacMarkdownView: NSView {
  private let markdown = MarkdownTextView()
  private var height: NSLayoutConstraint!

  init(markdown text: String) {
    super.init(frame: .zero)
    markdown.translatesAutoresizingMaskIntoConstraints = false
    addSubview(markdown)
    height = heightAnchor.constraint(equalToConstant: 20)
    NSLayoutConstraint.activate([
      markdown.topAnchor.constraint(equalTo: topAnchor),
      markdown.leadingAnchor.constraint(equalTo: leadingAnchor),
      markdown.trailingAnchor.constraint(equalTo: trailingAnchor),
      markdown.bottomAnchor.constraint(equalTo: bottomAnchor),
      height,
    ])
    markdown.setMarkdown(text)
    setAccessibilityIdentifier("transcript-prose")
  }

  required init?(coder: NSCoder) { nil }

  override func layout() {
    let next = ceil(markdown.boundingSize(for: bounds.width).height)
    if bounds.width > 0, abs(next - height.constant) > 0.5 { height.constant = max(next, 18) }
    super.layout()
  }
}

@MainActor
final class MacPlanView: NSView {
  init(markdown: String) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
    let label = NSTextField(labelWithString: String(localized: "mac.transcript.plan", bundle: .lodyMac))
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.textColor = .secondaryLabelColor
    let body = MacMarkdownView(markdown: markdown)
    let stack = NSStackView(views: [label, body])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor),
      body.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
    ])
    setAccessibilityIdentifier("transcript-plan")
  }

  required init?(coder: NSCoder) { nil }

  override func updateLayer() {
    layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
  }
}
