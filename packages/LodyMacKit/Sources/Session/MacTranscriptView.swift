import AppKit
import LodyData
import MarkdownView

@MainActor
final class MacTranscriptView: NSView {
  private let scroll = NSScrollView()
  private let column = NSStackView()
  private var rendered: [MacTranscriptItem] = []
  private var rows: [String: (item: MacTranscriptItem, view: NSView)] = [:]
  private var renderedCard: MacPermissionFlow.Card?
  private var cardView: MacPermissionCard?
  private var pinned = true
  private var userScrolling = false
  private var observers: [NSObjectProtocol] = []
  var onAnswer: ((String) -> Void)?
  var onRetry: (() -> Void)?

  var rowViews: [NSView] { column.arrangedSubviews.filter { $0 !== cardView } }

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
    document.postsFrameChangedNotifications = true
    scroll.contentView.postsFrameChangedNotifications = true
    scroll.contentView.postsBoundsChangedNotifications = true
    // Markdown rows settle their height after render and title bar insets arrive late, so the pin follows geometry.
    let geometry: [(NSNotification.Name, NSView)] = [
      (NSView.frameDidChangeNotification, document),
      (NSView.frameDidChangeNotification, scroll.contentView),
      (NSView.boundsDidChangeNotification, scroll.contentView),
    ]
    for (name, view) in geometry {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: view, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.followBottom() }
      })
    }
    let live: [(NSNotification.Name, Bool)] = [(NSScrollView.willStartLiveScrollNotification, true), (NSScrollView.didEndLiveScrollNotification, false)]
    for (name, scrolling) in live {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: scroll, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.userScrolling = scrolling
          if !scrolling { self.pinned = self.isScrolledToBottom }
        }
      })
    }
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  private func followBottom() {
    guard pinned, !userScrolling, let document = scroll.documentView else { return }
    let target = max(-scroll.contentInsets.top, document.frame.height - scroll.contentView.bounds.height + scroll.contentInsets.bottom)
    guard abs(scroll.contentView.bounds.origin.y - target) > 0.5 else { return }
    scroll.contentView.scroll(to: NSPoint(x: 0, y: target))
    scroll.reflectScrolledClipView(scroll.contentView)
  }

  func render(_ model: MacTranscriptModel, card: MacPermissionFlow.Card? = nil) {
    if model.items != rendered {
      rendered = model.items
      place(model.items)
    }
    if card != renderedCard {
      renderedCard = card
      cardView?.removeFromSuperview()
      cardView = card.map { card in
        let view = MacPermissionCard(card: card)
        view.onAnswer = { [weak self] in self?.onAnswer?($0) }
        add(view)
        return view
      }
    }
    if pinned { scrollToBottom() }
  }

  private func place(_ items: [MacTranscriptItem]) {
    var next: [String: (item: MacTranscriptItem, view: NSView)] = [:]
    var used = Set<ObjectIdentifier>()
    let views = items.map { item -> NSView in
      let reused = reuse(item).flatMap { used.contains(ObjectIdentifier($0)) ? nil : $0 }
      let view = reused ?? self.view(for: item)
      used.insert(ObjectIdentifier(view))
      next[item.id] = (item, view)
      return view
    }
    rows = next
    for view in rowViews where !used.contains(ObjectIdentifier(view)) { view.removeFromSuperview() }
    for (index, view) in views.enumerated() {
      let current = column.arrangedSubviews
      if index < current.count, current[index] === view { continue }
      view.removeFromSuperview()
      column.insertArrangedSubview(view, at: index)
      view.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -32).isActive = true
    }
  }

  private func reuse(_ item: MacTranscriptItem) -> NSView? {
    guard let old = rows[item.id] else { return nil }
    if old.item == item { return old.view }
    if case .prose(_, let markdown) = item, let view = old.view as? MacMarkdownView {
      view.update(markdown)
      return view
    }
    return nil
  }

  var isScrolledToBottom: Bool {
    guard let document = scroll.documentView else { return true }
    return scroll.contentView.bounds.maxY - scroll.contentInsets.bottom >= document.frame.height - 24
  }

  private func scrollToBottom() {
    layoutSubtreeIfNeeded()
    followBottom()
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
    case .subagent(_, let title, let detail, let running):
      return MacSubagentCard(title: title, detail: detail, running: running)
    case .failedSend(_, let text):
      let row = MacFailedSendView(text: text)
      row.onRetry = { [weak self] in self?.onRetry?() }
      return row
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

  func update(_ text: String) {
    markdown.setMarkdown(text)
    needsLayout = true
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
