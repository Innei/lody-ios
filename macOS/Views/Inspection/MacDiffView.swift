import AppKit
import LodyData
import LodyCore

@MainActor
enum MacInspectionUI {
  static func text(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .lodyMac) }
  static func button(_ title: String, _ id: String, _ invoke: @escaping () -> Void) -> NSButton {
    let button = MacActionButton(title: title, action: invoke)
    button.controlSize = .small; button.font = .systemFont(ofSize: 12)
    button.setAccessibilityIdentifier(id)
    return button
  }
  static func message(_ text: String, retry: (() -> Void)? = nil) -> NSView {
    let label = NSTextField(wrappingLabelWithString: text)
    label.textColor = .secondaryLabelColor; label.isSelectable = true
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
    case gap(String, Int)
    case line(InlineDiffLine)
    case message(String, String)
  }
  private let scroll = NSScrollView()
  private let table = NSTableView()
  private let column = NSTableColumn(identifier: .init("diff"))
  private var rows: [Row] = []
  private weak var model: MacInspectionModel?
  private var observing: NSObjectProtocol?
  private var rendering = false
  private var built: [String: [InlineDiffLine]] = [:]

  override init(frame: NSRect) {
    super.init(frame: frame)
    table.addTableColumn(column); table.headerView = nil; table.intercellSpacing = .zero
    table.selectionHighlightStyle = .none; table.backgroundColor = .textBackgroundColor
    table.dataSource = self; table.delegate = self
    table.setAccessibilityIdentifier("inspection-diff")
    scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true; scroll.drawsBackground = false
    scroll.translatesAutoresizingMaskIntoConstraints = false; addSubview(scroll)
    NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor), scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor)])
    scroll.contentView.postsBoundsChangedNotifications = true
    observing = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { guard let self, !self.rendering else { return }; self.model?.changesScroll = self.scroll.contentView.bounds.origin.y }
    }
  }
  required init?(coder: NSCoder) { nil }
  isolated deinit { if let observing { NotificationCenter.default.removeObserver(observing) } }

  func render(_ model: MacInspectionModel) {
    self.model = model; rendering = true; rows = []
    for file in model.files {
      let expanded = model.expanded.contains(file.path)
      rows.append(.file(file, expanded))
      guard expanded else { continue }
      let load = model.diffs[file.path]
      if let error = load?.error { rows.append(.message(file.path, error)) }
      guard let value = load?.value else {
        if load?.error == nil { rows.append(.message(file.path, MacInspectionUI.text("mac.inspection.loading"))) }
        continue
      }
      guard let stored = ContentStore.shared.get(value.handle),
            let diff = try? JSONDecoder().decode(RuntimeContract.DiffResultOk.self, from: stored.data) else {
        rows.append(.message(file.path, MacInspectionUI.text("mac.inspection.evicted"))); continue
      }
      if [value.oldKind, value.newKind].contains("binary") || [value.oldKind, value.newKind].contains("too_large") {
        rows.append(.message(file.path, MacInspectionUI.text("mac.inspection.binaryDiff"))); continue
      }
      let old = diff.old.text ?? "", new = diff.new.text ?? ""
      guard old.utf8.count + new.utf8.count <= 1024 * 1024, old.filter({ $0 == "\n" }).count + new.filter({ $0 == "\n" }).count <= 10000 else {
        rows.append(.message(file.path, MacInspectionUI.text("mac.inspection.tooLarge"))); continue
      }
      let lines: [InlineDiffLine]
      if let cached = built[value.handle] { lines = cached }
      else {
        lines = InlineDiffModel.rows(old: old, new: new)
        if built.count > 12 { built.removeAll() }
        built[value.handle] = lines
      }
      var index = 0
      while index < lines.count {
        if !model.showContext.contains(file.path), lines[index].kind == .context {
          var end = index
          while end < lines.count, lines[end].kind == .context { end += 1 }
          if end - index > 8 {
            for line in lines[index..<min(index + 3, end)] { rows.append(.line(line)) }
            rows.append(.gap(file.path, end - index - 6))
            for line in lines[max(index, end - 3)..<end] { rows.append(.line(line)) }
            index = end; continue
          }
        }
        rows.append(.line(lines[index])); index += 1
      }
    }
    var textWidth = bounds.width
    for row in rows { if case .line(let line) = row { textWidth = max(textWidth, CGFloat(min(3000, line.text.utf16.count)) * 7 + 112) } }
    column.width = max(320, textWidth)
    table.reloadData(); table.layoutSubtreeIfNeeded()
    scroll.contentView.scroll(to: .init(x: scroll.contentView.bounds.minX, y: model.changesScroll))
    scroll.reflectScrolledClipView(scroll.contentView); rendering = false
  }

  func reveal(_ path: String) {
    guard let index = rows.firstIndex(where: { if case .file(let f, _) = $0 { return f.path == path }; return false }) else { return }
    table.scrollRowToVisible(index)
  }
  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    switch rows[row] { case .file: 40; case .gap: 28; case .line: 22; case .message: 52 }
  }
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let model else { return nil }
    switch rows[row] {
    case .file(let file, let expanded):
      let toggle = MacInspectionUI.button((expanded ? "⌄ " : "› ") + file.path, "inspection-diff-" + file.path) { [weak model] in model?.toggleDiff(file.path) }
      toggle.isBordered = false; toggle.alignment = .left; toggle.lineBreakMode = .byTruncatingMiddle; toggle.toolTip = file.path
      let preview = MacInspectionUI.button("", "inspection-preview-" + file.path) { [weak model] in model?.show(.file(file.path)) }
      preview.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)
      preview.setAccessibilityLabel(MacInspectionUI.text("mac.inspection.preview") + " " + file.path)
      preview.isBordered = false
      let header = NSStackView(views: [toggle])
      if let add = file.add { let label = NSTextField(labelWithString: "+\(add)"); label.textColor = .systemGreen; header.addArrangedSubview(label) }
      if let del = file.del { let label = NSTextField(labelWithString: "−\(del)"); label.textColor = .systemRed; header.addArrangedSubview(label) }
      header.addArrangedSubview(preview); header.spacing = 6
      header.edgeInsets = .init(top: 4, left: 8, bottom: 4, right: 8)
      header.widthAnchor.constraint(equalToConstant: max(300, scroll.contentSize.width)).isActive = true
      toggle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      toggle.setContentHuggingPriority(.defaultLow, for: .horizontal)
      return header
    case .line(let line):
      let field = NSTextField(labelWithString: "")
      field.isSelectable = true; field.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
      field.lineBreakMode = .byClipping
      let sign: String, fill: NSColor
      switch line.kind { case .context: sign = " "; fill = .clear; case .insert: sign = "+"; fill = .systemGreen.withAlphaComponent(0.11); case .delete: sign = "−"; fill = .systemRed.withAlphaComponent(0.11) }
      field.drawsBackground = true; field.backgroundColor = fill
      let prefix = String(format: "%5@ %5@  %@  ", line.oldNumber.map(String.init) ?? "", line.newNumber.map(String.init) ?? "", sign)
      let value = NSMutableAttributedString(string: prefix, attributes: [.foregroundColor: NSColor.secondaryLabelColor])
      value.append(MacInspectionSyntax.code(line.text))
      field.attributedStringValue = value
      return field
    case .gap(let path, let count):
      let title = String.localizedStringWithFormat(MacInspectionUI.text("mac.inspection.unmodified"), count)
      return MacInspectionUI.button(title, "inspection-context-" + path) { [weak self, weak model] in guard let self, let model else { return }; model.showContext.insert(path); render(model) }
    case .message(let path, let message):
      return MacInspectionUI.button(message + " · " + MacInspectionUI.text("mac.inspection.retry"), "inspection-retry-" + path) { [weak model] in model?.loadDiff(path, force: true) }
    }
  }
}

@MainActor
enum MacInspectionSyntax {
  static func code(_ text: String) -> NSAttributedString {
    let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular), .foregroundColor: NSColor.labelColor])
    let range = NSRange(location: 0, length: (text as NSString).length)
    for (pattern, color) in [("\\b(import|class|struct|enum|func|let|var|if|else|return|guard|private|public|final|async|await|throws|true|false|nil)\\b", NSColor.systemPurple), ("\"[^\"]*\"", NSColor.systemOrange), ("//.*$", NSColor.secondaryLabelColor)] {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      for match in regex.matches(in: text, range: range) { value.addAttribute(.foregroundColor, value: color, range: match.range) }
    }
    return value
  }
}
