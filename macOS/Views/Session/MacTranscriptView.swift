import AppKit
import ChatAppKit
import ChatKitCore
import LodyData
import MarkdownView

@MainActor
final class MacTranscriptView: NSView, MacFileDropTarget {
  private let table = CKTranscriptTable()
  private var scroll: NSScrollView { table.scrollView }
  private var items: [String: MacTranscriptItem] = [:]
  private var changeBlocks: [String: [MacTranscriptItem]] = [:]
  private var changedFiles: [String: ChatFileDiff] = [:]
  var onRetry: (() -> Void)?
  var onPreview: ((CKMediaRef) -> Void)?
  var onChanges: ((String) -> Void)?
  var onDropFiles: (([URL]) -> Void)?
  var media: CKMediaProvider?

  var rowViews: [NSView] {
    table.layoutSubtreeIfNeeded()
    return table.instantiatedContentViews.filter { !($0 is CKHistoryHeaderView) }
  }

  var reading = MacReading.current() {
    didSet {
      table.readingWidth = reading.columnWidth
      guard reading.textSize != oldValue.textSize else { return }
      table.reloadAll()
    }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    table.horizontalInset = 20
    table.readingWidth = reading.columnWidth
    table.tableView.setAccessibilityIdentifier("transcript")
    registerForDraggedTypes([.fileURL])
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

  func focus() {
    window?.makeFirstResponder(table.tableView)
  }

  func dropFiles(_ urls: [URL]) {
    onDropFiles?(urls)
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    onDropFiles == nil || MacComposerView.fileURLs(sender.draggingPasteboard).isEmpty ? [] : .copy
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = MacComposerView.fileURLs(sender.draggingPasteboard)
    guard !urls.isEmpty, onDropFiles != nil else { return false }
    dropFiles(urls)
    return true
  }

  func render(_ model: MacTranscriptModel) {
    let arrived = model.items.filter { ["user", "attachments"].contains($0.kind) && items[$0.id] == nil }.map(\.id)
    items = Dictionary(model.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    changedFiles = model.changedFiles
    let blocks = Dictionary(grouping: model.items.filter { $0.kind == "changes" }) { model.groups[$0.id] ?? $0.id }
    changeBlocks = Dictionary(uniqueKeysWithValues: blocks.values.compactMap { block in block.first.map { ($0.id, block) } })
    let hidden = Set(changeBlocks.values.flatMap { $0.dropFirst().map(\.id) })
    let rows = model.items.filter { !hidden.contains($0.id) }.map { item in
      var version = Hasher(); version.combine(item)
      for file in changeBlocks[item.id] ?? [] { version.combine(file); version.combine(changedFiles[file.id]?.add); version.combine(changedFiles[file.id]?.del) }
      return CKTranscriptRow(
        id: item.id, kind: item.kind, neighbourKey: item.kind, version: version.finalize(),
        group: model.groups[item.id] ?? item.id, deferrable: model.streaming.contains(item.id)
      )
    }
    table.apply(rows)
    if let sent = arrived.first { table.anchor(rowID: sent) }
  }

  var isScrolledToBottom: Bool {
    guard let document = scroll.documentView else { return true }
    return scroll.contentView.bounds.maxY - scroll.contentInsets.bottom >= document.frame.height - 24
  }

  private func cell(for row: CKTranscriptRow, reused: NSView?) -> NSView {
    guard let item = items[row.id] else { return reused ?? NSView() }
    if case .prose(_, let markdown) = item, let view = reused as? MacMarkdownView, view.size == reading.textSize {
      view.update(markdown)
      return view
    }
    if case .image(_, let media, _, _) = item, let view = reused as? MacTranscriptImageView, view.media == media {
      return view
    }
    if case .attachments(_, let files) = item, let view = reused as? MacTranscriptAttachmentsView {
      view.update(files)
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
    case .changes(let id, _):
      return MacTranscriptChangesBlock(items: changeBlocks[id] ?? [item], files: changedFiles) { [weak self] id in self?.onChanges?(id) }
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
    case .image(_, let media, let name, let aspect):
      let view = MacTranscriptImageView(media: media, name: name, aspect: aspect, provider: self.media)
      view.onPreview = { [weak self] in self?.onPreview?($0) }
      return view
    case .attachments(_, let files):
      let view = MacTranscriptAttachmentsView(files: files, provider: media)
      view.onPreview = { [weak self] in self?.onPreview?($0) }
      return view
    }
  }
}

@MainActor
private final class MacTranscriptChangesBlock: MacInspectionSurface {
  init(items: [MacTranscriptItem], files: [String: ChatFileDiff], open: @escaping (String) -> Void) {
    super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 36 * min(items.count, 4) + 7))
    fill = MacInspectionUI.insetColor; radius = 10
    let column = NSStackView(); column.orientation = .vertical; column.alignment = .leading; column.spacing = 0
    column.translatesAutoresizingMaskIntoConstraints = false; addSubview(column)
    NSLayoutConstraint.activate([column.leadingAnchor.constraint(equalTo: leadingAnchor), column.trailingAnchor.constraint(equalTo: trailingAnchor), column.topAnchor.constraint(equalTo: topAnchor), column.bottomAnchor.constraint(equalTo: bottomAnchor)])
    let visible = items.count > 4 ? Array(items.prefix(4)) : items
    for (index, item) in visible.enumerated() {
      guard case .changes(let id, let text) = item else { continue }
      let file = files[id]
      let summary = file?.path.isEmpty == true || file == nil
      let title = summary ? text : (text as NSString).lastPathComponent
      let button = MacActionButton(title: title) { open(id) }
      button.isBordered = false; button.alignment = .left; button.lineBreakMode = .byTruncatingMiddle
      button.font = .systemFont(ofSize: summary ? 12 : 11, weight: summary ? .medium : .regular)
      button.contentTintColor = summary ? .labelColor : .secondaryLabelColor
      button.setContentHuggingPriority(.defaultLow, for: .horizontal); button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      button.toolTip = text; button.setAccessibilityIdentifier("transcript-changes"); button.setAccessibilityLabel(text)
      let glyph = NSImageView(image: NSImage(systemSymbolName: summary ? "arrow.triangle.branch" : "doc.text", accessibilityDescription: nil) ?? NSImage())
      glyph.contentTintColor = .secondaryLabelColor; glyph.symbolConfiguration = .init(pointSize: 12, weight: .regular); glyph.widthAnchor.constraint(equalToConstant: 16).isActive = true
      let row = NSStackView(views: [glyph, button]); row.spacing = 8; row.distribution = .fill
      row.edgeInsets = .init(top: 0, left: 12, bottom: 0, right: 12)
      if let add = file?.add { row.addArrangedSubview(MacInspectionUI.label("+\(add)", size: 11, color: .systemGreen)) }
      if let del = file?.del { row.addArrangedSubview(MacInspectionUI.label("−\(del)", size: 11, color: .systemRed)) }
      if summary { row.addArrangedSubview(MacInspectionUI.icon("sidebar.right", title: MacInspectionUI.text("mac.inspection.changes"), id: "transcript-open-changes", size: 20) { _ in open(id) }) }
      column.addArrangedSubview(row)
      row.heightAnchor.constraint(equalToConstant: summary ? 42 : 36).isActive = true; row.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
      if index == 0, visible.count > 1 { let rule = NSBox(); rule.boxType = .separator; column.addArrangedSubview(rule); rule.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
    }
  }
  required init?(coder: NSCoder) { nil }
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
