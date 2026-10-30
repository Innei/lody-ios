import AppKit
import ChatAppKit
import LodyData
import MarkdownView

@MainActor
final class MacTranscriptView: NSView {
  private let table = CKTranscriptTable()
  private var scroll: NSScrollView { table.scrollView }
  private var items: [String: MacTranscriptItem] = [:]
  private var renderedCard: MacPermissionFlow.Card?
  private var cardVersion = 0
  var onAnswer: ((String) -> Void)?
  var onRetry: (() -> Void)?

  var rowViews: [NSView] {
    table.layoutSubtreeIfNeeded()
    return table.instantiatedContentViews.filter { !($0 is MacPermissionCard || $0 is CKHistoryHeaderView) }
  }

  var reading = MacReading.current() {
    didSet {
      table.readingWidth = reading.fillWidth ? nil : 780
      guard reading.textSize != oldValue.textSize else { return }
      table.reloadAll()
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    table.readingWidth = reading.fillWidth ? nil : 780
    table.tableView.setAccessibilityIdentifier("transcript")
    table.historyHeader.labels = .init(
      more: String(localized: "mac.transcript.history.more", bundle: .lodyMac),
      start: String(localized: "mac.transcript.history.start", bundle: .lodyMac)
    )
    table.cell = { [weak self] row, reused in
      self?.cell(for: row, reused: reused) ?? NSView()
    }
    table.translatesAutoresizingMaskIntoConstraints = false
    addSubview(table)
    NSLayoutConstraint.activate([
      table.topAnchor.constraint(equalTo: topAnchor),
      table.leadingAnchor.constraint(equalTo: leadingAnchor),
      table.trailingAnchor.constraint(equalTo: trailingAnchor),
      table.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  required init?(coder: NSCoder) { nil }

  func noteSend() {
    table.follow(.send(queued: false))
  }

  func render(_ model: MacTranscriptModel, card: MacPermissionFlow.Card? = nil) {
    if card != renderedCard {
      renderedCard = card
      cardVersion += 1
    }
    let arrived = model.items.filter { $0.kind == "user" && items[$0.id] == nil }.map(\.id)
    items = Dictionary(model.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    var rows = model.items.map { item in
      CKTranscriptRow(
        id: item.id, kind: item.kind, neighbourKey: item.kind, version: item.hashValue,
        group: model.groups[item.id] ?? item.id, deferrable: model.streaming.contains(item.id)
      )
    }
    if card != nil {
      rows.append(CKTranscriptRow(id: Self.cardID, kind: "permission", neighbourKey: "permission", version: cardVersion, group: Self.cardID))
    }
    table.apply(rows)
    if let sent = arrived.last { table.anchor(rowID: sent) }
  }

  var isScrolledToBottom: Bool {
    guard let document = scroll.documentView else { return true }
    return scroll.contentView.bounds.maxY - scroll.contentInsets.bottom >= document.frame.height - 24
  }

  private static let cardID = "permission-card"

  private func cell(for row: CKTranscriptRow, reused: NSView?) -> NSView {
    if row.id == Self.cardID, let card = renderedCard {
      let view = MacPermissionCard(card: card)
      view.onAnswer = { [weak self] in self?.onAnswer?($0) }
      return view
    }
    guard let item = items[row.id] else { return reused ?? NSView() }
    if case .prose(_, let markdown) = item, let view = reused as? MacMarkdownView, view.size == reading.textSize {
      view.update(markdown)
      return view
    }
    return view(for: item)
  }

  private func view(for item: MacTranscriptItem) -> NSView {
    switch item {
    case .user(_, let text): return MacUserTurnView(text: text, size: reading.textSize)
    case .prose(_, let markdown): return MacMarkdownView(markdown: markdown, size: reading.textSize)
    case .plan(_, let markdown): return MacPlanView(markdown: markdown, size: reading.textSize)
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

  var bodyFont: NSFont { markdown.theme.fonts.body }
  let size: Double

  init(markdown text: String, size: Double = MacReading.standard.textSize) {
    self.size = size
    super.init(frame: .zero)
    var theme = markdown.theme
    theme.align(to: size)
    markdown.theme = theme
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
    setAccessibilityElement(true)
    setAccessibilityRole(.staticText)
    setAccessibilityValue(Self.plain(text))
    setAccessibilityIdentifier("transcript-prose")
  }

  func update(_ text: String) {
    markdown.setMarkdown(text)
    setAccessibilityValue(Self.plain(text))
    needsLayout = true
  }

  private static func plain(_ markdown: String) -> String {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: markdown, options: options)).map { String($0.characters) } ?? markdown
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
  init(markdown: String, size: Double = MacReading.standard.textSize) {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
    let label = NSTextField(labelWithString: String(localized: "mac.transcript.plan", bundle: .lodyMac))
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.textColor = .secondaryLabelColor
    let body = MacMarkdownView(markdown: markdown, size: size)
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
