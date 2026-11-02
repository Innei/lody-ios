import AppKit
import LodyData
import LodyCore

@MainActor
enum MacInspectionUI {
  static var insetColor: NSColor {
    NSColor(name: "MacInspectionInset") { appearance in
      let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.965, alpha: 1)
    }
  }
  static func text(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .lodyMac) }
  static func button(_ title: String, _ id: String, _ invoke: @escaping () -> Void) -> NSButton {
    let button = MacActionButton(title: title, action: invoke)
    button.controlSize = .small; button.font = .systemFont(ofSize: 12)
    button.setAccessibilityIdentifier(id)
    return button
  }
  static func icon(_ symbol: String, title: String, id: String, size: CGFloat = 28, _ invoke: @escaping (NSView) -> Void) -> NSButton {
    let button = MacInspectionIconButton()
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size < 24 ? 10 : 14, weight: .regular))
    button.toolTip = title; button.setAccessibilityLabel(title); button.setAccessibilityIdentifier(id); button.invoke = invoke
    button.widthAnchor.constraint(equalToConstant: size).isActive = true
    button.heightAnchor.constraint(equalToConstant: size).isActive = true
    return button
  }
  static func label(_ text: String, size: CGFloat = 12, color: NSColor = .secondaryLabelColor) -> NSTextField {
    let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: size); label.textColor = color
    label.lineBreakMode = .byTruncatingMiddle
    return label
  }
  static func path(_ path: String, size: CGFloat = 12) -> NSAttributedString {
    let prefix = (path as NSString).deletingLastPathComponent
    let text = NSMutableAttributedString(string: prefix.isEmpty ? "" : prefix + "/", attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.secondaryLabelColor])
    text.append(NSAttributedString(string: (path as NSString).lastPathComponent, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.labelColor]))
    return text
  }
  static func fileIcon(_ path: String) -> NSImageView {
    let ext = (path as NSString).pathExtension.lowercased()
    let symbols = ["swift": "swift", "png": "photo", "jpg": "photo", "jpeg": "photo", "pdf": "doc.richtext", "json": "curlybraces", "md": "text.document"]
    let image = NSImageView(image: NSImage(systemSymbolName: symbols[ext] ?? "doc.text", accessibilityDescription: nil) ?? NSImage())
    image.symbolConfiguration = .init(pointSize: 12, weight: .regular)
    image.contentTintColor = .secondaryLabelColor
    image.widthAnchor.constraint(equalToConstant: 22).isActive = true
    image.heightAnchor.constraint(equalToConstant: 22).isActive = true
    return image
  }
  static func message(_ text: String, retry: (() -> Void)? = nil) -> NSView {
    let label = NSTextField(wrappingLabelWithString: text)
    label.textColor = .secondaryLabelColor; label.font = .systemFont(ofSize: 12); label.isSelectable = true
    let stack = NSStackView(views: [label]); stack.orientation = .vertical; stack.spacing = 12
    stack.edgeInsets = .init(top: 24, left: 20, bottom: 24, right: 20)
    if let retry { stack.addArrangedSubview(button(Self.text("mac.inspection.retry"), "inspection-retry", retry)) }
    return stack
  }
}

@MainActor
final class MacDiffView: NSView, NSTableViewDataSource, NSTableViewDelegate {
  private enum Row {
    case file(MacInspectionFile, Bool)
    case gap(String, String, Int)
    case more(String, Int)
    case line(InlineDiffLine)
    case message(String, String, Bool)
  }
  private let scroll = NSScrollView()
  private let table = NSTableView()
  private let column = NSTableColumn(identifier: .init("diff"))
  private var rows: [Row] = []
  private weak var model: MacInspectionModel?
  private var observing: NSObjectProtocol?
  private var rendering = false
  private var built: [String: [InlineDiffLine]] = [:]
  var filter = "" { didSet { if let model { render(model) } } }

  override init(frame: NSRect) {
    super.init(frame: frame)
    table.addTableColumn(column); table.headerView = nil; table.intercellSpacing = .zero
    table.style = .plain; table.floatsGroupRows = true; table.columnAutoresizingStyle = .noColumnAutoresizing
    table.selectionHighlightStyle = .none; table.backgroundColor = .textBackgroundColor
    table.dataSource = self; table.delegate = self
    table.setAccessibilityIdentifier("inspection-diff")
    scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
    scroll.scrollerStyle = .overlay; scroll.autohidesScrollers = true; scroll.drawsBackground = false
    scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
    NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor), scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor)])
    scroll.contentView.postsBoundsChangedNotifications = true
    observing = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if !self.rendering { self.model?.changesScroll = self.scroll.contentView.bounds.origin.y }
        self.updateHeaders()
      }
    }
  }
  required init?(coder: NSCoder) { nil }
  isolated deinit { if let observing { NotificationCenter.default.removeObserver(observing) } }
  override func layout() { super.layout(); resizeColumn(); updateHeaders() }

  func render(_ model: MacInspectionModel) {
    self.model = model; rendering = true; rows = []
    for file in model.files where filter.isEmpty || file.path.localizedCaseInsensitiveContains(filter) {
      let expanded = model.expanded.contains(file.path)
      rows.append(.file(file, expanded))
      guard expanded else { continue }
      let load = model.diffs[file.path]
      if let error = load?.error { rows.append(.message(file.path, error, true)) }
      guard let value = load?.value else {
        if load?.error == nil { rows.append(.message(file.path, MacInspectionUI.text("mac.inspection.loading"), false)) }
        continue
      }
      guard let stored = ContentStore.shared.get(value.handle), let diff = try? JSONDecoder().decode(RuntimeContract.DiffResultOk.self, from: stored.data) else {
        rows.append(.message(file.path, MacInspectionUI.text("mac.inspection.evicted"), true)); continue
      }
      if [value.oldKind, value.newKind].contains("binary") || [value.oldKind, value.newKind].contains("too_large") {
        rows.append(.message(file.path, MacInspectionUI.text("mac.inspection.binaryDiff"), false)); continue
      }
      let old = diff.old.text ?? "", new = diff.new.text ?? ""
      guard old.utf8.count + new.utf8.count <= 1024 * 1024, old.filter({ $0 == "\n" }).count + new.filter({ $0 == "\n" }).count <= 10000 else {
        rows.append(.message(file.path, MacInspectionUI.text("mac.inspection.tooLarge"), false)); continue
      }
      let lines: [InlineDiffLine]
      if let cached = built[value.handle] { lines = cached }
      else {
        lines = InlineDiffModel.rows(old: old, new: new)
        if built.count > 12 { built.removeAll() }
        built[value.handle] = lines
      }
      var hunks: [Range<Int>] = []
      for index in lines.indices where lines[index].kind != .context {
        if let last = hunks.last, index - last.upperBound <= 6 { hunks[hunks.count - 1] = last.lowerBound..<index + 1 }
        else { hunks.append(index..<index + 1) }
      }
      let limited = hunks.count > 2 && !model.showAllHunks.contains(file.path)
      let endOfPreview = limited ? min(lines.count, hunks[1].upperBound + 3) : lines.count
      var index = 0
      while index < endOfPreview {
        if lines[index].kind == .context {
          var end = index
          while end < endOfPreview, lines[end].kind == .context { end += 1 }
          let key = file.path + ":" + String(index)
          if end - index > 8, !model.showContext.contains(key) {
            let leading = index == 0 ? 0 : 3
            let trailing = end == lines.count ? 0 : 3
            for line in lines[index..<index + leading] { rows.append(.line(line)) }
            rows.append(.gap(file.path, key, end - index - leading - trailing))
            for line in lines[end - trailing..<end] { rows.append(.line(line)) }
          } else { for line in lines[index..<end] { rows.append(.line(line)) } }
          index = end; continue
        }
        rows.append(.line(lines[index])); index += 1
      }
      if limited { rows.append(.more(file.path, hunks.count - 2)) }
    }
    if rows.isEmpty, !filter.isEmpty { rows.append(.message("", MacInspectionUI.text("mac.inspection.noMatching"), false)) }
    resizeColumn()
    table.reloadData(); table.layoutSubtreeIfNeeded()
    scroll.contentView.scroll(to: .init(x: scroll.contentView.bounds.minX, y: filter.isEmpty ? model.changesScroll : 0))
    scroll.reflectScrolledClipView(scroll.contentView); rendering = false; updateHeaders()
  }

  private func resizeColumn() {
    var width = max(320, scroll.contentSize.width)
    for row in rows { if case .line(let line) = row { width = max(width, (line.text as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)]).width + 112) } }
    if abs(column.width - width) > 0.5 { column.width = width }
  }
  private func updateHeaders() {
    let visible = table.rows(in: table.visibleRect)
    guard visible.location != NSNotFound else { return }
    for index in visible.location..<min(rows.count, NSMaxRange(visible)) {
      (table.view(atColumn: 0, row: index, makeIfNecessary: false) as? MacDiffFileHeader)?.viewport(scroll.contentView.bounds.minX, width: scroll.contentSize.width)
    }
  }
  func reveal(_ path: String) {
    guard let index = rows.firstIndex(where: { if case .file(let f, _) = $0 { return f.path == path }; return false }) else { return }
    table.scrollRowToVisible(index)
  }
  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
  func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { if case .file = rows[row] { return true }; return false }
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { switch rows[row] { case .file: 46; case .gap, .more: 29; case .line: 22; case .message: 58 } }
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let model else { return nil }
    switch rows[row] {
    case .file(let file, let expanded):
      let header = MacDiffFileHeader(file: file, expanded: expanded, toggle: { [weak model] in model?.toggleDiff(file.path) }, preview: { [weak model] in model?.show(.file(file.path)) })
      header.viewport(scroll.contentView.bounds.minX, width: scroll.contentSize.width)
      return header
    case .line(let line): return MacDiffLineView(line: line)
    case .gap(let path, let key, let count):
      let button = MacInspectionUI.button(String.localizedStringWithFormat(MacInspectionUI.text("mac.inspection.unmodified"), count), "inspection-context-" + path) { [weak self, weak model] in guard let self, let model else { return }; model.showContext.insert(key); render(model) }
      button.isBordered = false; button.alignment = .left; button.font = .systemFont(ofSize: 11)
      button.contentTintColor = .secondaryLabelColor
      button.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 9, weight: .regular)); button.imagePosition = .imageLeading
      let surface = MacInspectionSurface(); surface.fill = MacInspectionUI.insetColor
      button.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(button)
      NSLayoutConstraint.activate([button.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 14), button.centerYAnchor.constraint(equalTo: surface.centerYAnchor)])
      return surface
    case .more(let path, let count):
      let button = MacInspectionUI.button(String.localizedStringWithFormat(MacInspectionUI.text("mac.inspection.moreHunks"), count), "inspection-more-hunks-" + path) { [weak self, weak model] in guard let self, let model else { return }; model.showAllHunks.insert(path); render(model) }
      button.isBordered = false; button.alignment = .left; button.font = .systemFont(ofSize: 11); button.contentTintColor = .secondaryLabelColor
      button.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 10, weight: .regular)); button.imagePosition = .imageLeading
      let surface = MacInspectionSurface(); surface.fill = MacInspectionUI.insetColor
      button.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(button)
      NSLayoutConstraint.activate([button.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 14), button.centerYAnchor.constraint(equalTo: surface.centerYAnchor)])
      return surface
    case .message(let path, let text, let retry):
      let surface = MacInspectionSurface(); surface.fill = MacInspectionUI.insetColor
      let label = MacInspectionUI.label(text, size: 11)
      let row = NSStackView(views: [label]); row.spacing = 8
      if retry { row.addArrangedSubview(MacInspectionUI.button(MacInspectionUI.text("mac.inspection.retry"), "inspection-retry-" + path) { [weak model] in model?.loadDiff(path, force: true) }) }
      row.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(row)
      NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16), row.centerYAnchor.constraint(equalTo: surface.centerYAnchor), row.trailingAnchor.constraint(lessThanOrEqualTo: surface.trailingAnchor, constant: -16)])
      return surface
    }
  }
}

@MainActor
private final class MacDiffFileHeader: MacInspectionSurface {
  private let content = NSStackView()
  private let filePath: String
  private var pathButton: NSButton?
  init(file: MacInspectionFile, expanded: Bool, toggle: @escaping () -> Void, preview: @escaping () -> Void) {
    filePath = file.path
    super.init(frame: .zero); bottomRule = true
    let disclosure = NSImageView(image: NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil) ?? NSImage())
    disclosure.symbolConfiguration = .init(pointSize: 8, weight: .regular); disclosure.contentTintColor = .tertiaryLabelColor
    disclosure.widthAnchor.constraint(equalToConstant: 10).isActive = true
    let button = MacInspectionUI.button(file.path, "inspection-diff-" + file.path, toggle)
    button.isBordered = false; button.alignment = .left; button.attributedTitle = MacInspectionUI.path(file.path); button.lineBreakMode = .byTruncatingMiddle; button.toolTip = file.path
    button.setAccessibilityLabel(file.path); pathButton = button
    button.setContentHuggingPriority(.defaultLow, for: .horizontal); button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    content.setViews([disclosure, MacInspectionUI.fileIcon(file.path), button], in: .leading)
    if let add = file.add { content.addArrangedSubview(MacInspectionUI.label("+\(add)", color: .systemGreen)) }
    if let del = file.del { content.addArrangedSubview(MacInspectionUI.label("−\(del)", color: .systemRed)) }
    content.addArrangedSubview(MacInspectionUI.icon("doc.text.magnifyingglass", title: MacInspectionUI.text("mac.inspection.preview") + " " + file.path, id: "inspection-preview-" + file.path, size: 25) { _ in preview() })
    content.distribution = .fill; content.spacing = 7; content.edgeInsets = .init(top: 0, left: 10, bottom: 0, right: 10)
    addSubview(content)
  }
  required init?(coder: NSCoder) { nil }
  func viewport(_ x: CGFloat, width: CGFloat) {
    pathButton?.attributedTitle = MacInspectionUI.path(width < 480 ? (filePath as NSString).lastPathComponent : filePath)
    content.frame = NSRect(x: x, y: 0, width: max(300, width), height: 46)
  }
}

@MainActor
private final class MacDiffLineView: NSView {
  private let line: InlineDiffLine
  init(line: InlineDiffLine) {
    self.line = line; super.init(frame: .zero)
    let code = NSTextField(labelWithString: "")
    code.attributedStringValue = MacInspectionSyntax.code(line.text); code.isSelectable = true
    code.lineBreakMode = .byClipping; code.focusRingType = .none
    code.translatesAutoresizingMaskIntoConstraints = false; addSubview(code)
    NSLayoutConstraint.activate([code.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 96), code.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), code.centerYAnchor.constraint(equalTo: centerYAnchor)])
  }
  required init?(coder: NSCoder) { nil }
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    let tint: NSColor
    switch line.kind { case .insert: tint = .systemGreen; case .delete: tint = .systemRed; case .context: tint = .secondaryLabelColor }
    if line.kind != .context { tint.withAlphaComponent(0.10).setFill(); bounds.fill() }
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular), .foregroundColor: tint]
    for (number, x) in [(line.oldNumber, CGFloat(0)), (line.newNumber, CGFloat(37))] {
      if let number { let value = String(number) as NSString; let width = value.size(withAttributes: attrs).width; value.draw(at: .init(x: x + 29 - width, y: 4), withAttributes: attrs) }
    }
    let sign: String
    switch line.kind { case .insert: sign = "+"; case .delete: sign = "−"; case .context: sign = "" }
    (sign as NSString).draw(at: .init(x: 80, y: 4), withAttributes: attrs)
    NSColor.separatorColor.withAlphaComponent(0.2).setFill()
    NSRect(x: 37, y: 0, width: 0.5, height: bounds.height).fill(); NSRect(x: 74, y: 0, width: 0.5, height: bounds.height).fill()
  }
}

@MainActor
enum MacInspectionSyntax {
  static func code(_ text: String) -> NSAttributedString {
    let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular), .foregroundColor: NSColor.labelColor])
    let range = NSRange(location: 0, length: (text as NSString).length)
    for (pattern, color) in [("\\b(import|class|struct|enum|func|let|var|if|else|return|guard|private|public|final|async|await|throws|true|false|nil|override|super|self|for|in|case|switch|try)\\b", NSColor.systemPurple), ("\"[^\"]*\"", NSColor.systemOrange), ("//.*$", NSColor.secondaryLabelColor)] {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      for match in regex.matches(in: text, range: range) { value.addAttribute(.foregroundColor, value: color, range: match.range) }
    }
    return value
  }
}
