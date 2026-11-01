import AppKit

@MainActor
final class MacDiffController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  let model: MacDiffModel
  private let table = NSTableView()
  private let code = NSTextView()
  private let status = NSTextField(wrappingLabelWithString: "")
  private let base = NSTextField(labelWithString: "")
  private let scope = NSSegmentedControl()
  private let spinner = NSProgressIndicator()
  private var renderedFiles: [MacChangedFile] = []
  private var renderedPatch = ""
  private var rendering = false
  private var copy: NSButton?
  private var retry: NSButton?
  private var task: Task<Void, Never>?

  init(model: MacDiffModel) {
    self.model = model
    super.init(nibName: nil, bundle: nil)
    model.changed = { [weak self] in self?.render() }
  }
  required init?(coder: NSCoder) { nil }
  isolated deinit { task?.cancel() }

  override func loadView() {
    preferredContentSize = NSSize(width: 940, height: 600)
    let root = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
    let heading = NSTextField(labelWithString: Self.text("mac.diff.title"))
    heading.font = .preferredFont(forTextStyle: .title2)
    let close = button("mac.diff.close", "diff-close") { [weak self] in self?.dismiss(nil) }
    let refresh = button("mac.diff.refresh", "diff-refresh") { [weak self] in self?.load() }
    let copy = button("mac.diff.copy", "diff-copy") { [weak self] in
      guard let self, !model.patch.isEmpty else { return }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(model.patch, forType: .string)
    }
    self.copy = copy
    retry = refresh
    let header = NSStackView(views: [heading, NSView(), copy, refresh, close])
    header.spacing = 8
    scope.segmentCount = 2
    scope.setLabel(Self.text("mac.diff.thisTurn"), forSegment: 0)
    scope.setLabel(Self.text("mac.diff.all"), forSegment: 1)
    scope.selectedSegment = model.scope == .turn ? 0 : 1
    scope.isHidden = model.entryId == nil
    scope.target = self
    scope.action = #selector(scopeChanged)
    scope.setAccessibilityIdentifier("diff-scope")
    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false
    base.textColor = .secondaryLabelColor
    base.setAccessibilityIdentifier("diff-base")
    let info = NSStackView(views: [scope, base, NSView(), spinner])
    info.spacing = 12
    let column = NSTableColumn(identifier: .init("file"))
    column.title = Self.text("mac.diff.files")
    column.width = 220
    table.addTableColumn(column)
    table.headerView = nil
    table.dataSource = self
    table.delegate = self
    table.rowSizeStyle = .medium
    table.style = .plain
    table.setAccessibilityIdentifier("diff-files")
    let fileScroll = NSScrollView()
    fileScroll.documentView = table
    fileScroll.hasVerticalScroller = true
    let codeScroll = NSScrollView()
    codeScroll.documentView = code
    codeScroll.hasVerticalScroller = true
    codeScroll.hasHorizontalScroller = true
    code.isEditable = false
    code.isSelectable = true
    code.isRichText = false
    code.drawsBackground = true
    code.backgroundColor = .textBackgroundColor
    code.textContainerInset = NSSize(width: 12, height: 12)
    code.isVerticallyResizable = true
    code.isHorizontallyResizable = true
    code.minSize = .zero
    code.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    code.textContainer?.containerSize = code.maxSize
    code.textContainer?.widthTracksTextView = false
    code.autoresizingMask = [.width]
    code.setAccessibilityIdentifier("diff-patch")
    let content = NSStackView(views: [fileScroll, codeScroll])
    content.orientation = .horizontal
    content.alignment = .top
    content.spacing = 12
    fileScroll.widthAnchor.constraint(equalToConstant: 240).isActive = true
    codeScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
    fileScroll.heightAnchor.constraint(equalTo: content.heightAnchor).isActive = true
    codeScroll.heightAnchor.constraint(equalTo: content.heightAnchor).isActive = true
    status.textColor = .secondaryLabelColor
    status.setAccessibilityIdentifier("diff-status")
    let stack = NSStackView(views: [header, info, content, status])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
      content.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
    ])
    for child in [header, info, content, status] { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    root.setAccessibilityIdentifier("session-diff")
    view = root
    render()
    load()
  }

  private func load() { task?.cancel(); task = Task { await model.load() } }
  @objc private func scopeChanged() {
    task?.cancel()
    let next: MacDiffModel.Scope = scope.selectedSegment == 0 ? .turn : .session
    task = Task { await model.setScope(next) }
  }

  private func render() {
    guard isViewLoaded else { return }
    rendering = true
    defer { rendering = false }
    if renderedFiles != model.files { renderedFiles = model.files; table.reloadData() }
    if let selected = model.files.firstIndex(where: { $0.path == model.selectedPath }), table.selectedRow != selected {
      table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
    }
    if renderedPatch != model.patch {
      renderedPatch = model.patch
      code.textStorage?.setAttributedString(Self.attributedPatch(model.patch))
      code.scrollRangeToVisible(NSRange(location: 0, length: 0))
    }
    if model.loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
    status.stringValue = model.loading ? Self.text("mac.diff.loading") : model.message
    base.stringValue = model.base
    copy?.isEnabled = !model.loading && !model.patch.isEmpty
    retry?.isEnabled = !model.loading
  }

  func numberOfRows(in tableView: NSTableView) -> Int { model.files.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard model.files.indices.contains(row) else { return nil }
    let file = model.files[row]
    let label = NSTextField(labelWithString: file.title)
    label.lineBreakMode = .byTruncatingMiddle
    label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    label.toolTip = file.path
    label.setAccessibilityIdentifier("diff-file-\(row)")
    return label
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !rendering, model.files.indices.contains(table.selectedRow) else { return }
    let path = model.files[table.selectedRow].path
    task?.cancel()
    task = Task { await model.select(path) }
  }

  private static func attributedPatch(_ patch: String) -> NSAttributedString {
    let text = NSMutableAttributedString(string: "")
    for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
      var color = NSColor.textColor
      if line.hasPrefix("+") && !line.hasPrefix("+++") { color = .systemGreen }
      else if line.hasPrefix("-") && !line.hasPrefix("---") { color = .systemRed }
      else if line.hasPrefix("@@") || line.hasPrefix("---") || line.hasPrefix("+++") { color = .secondaryLabelColor }
      text.append(NSAttributedString(string: String(line) + "\n", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: color]))
    }
    return text
  }

  private func button(_ key: String, _ id: String, action: @escaping () -> Void) -> NSButton {
    let button = MacActionButton(title: Self.text(key), action: action)
    button.setAccessibilityIdentifier(id)
    return button
  }
  private static func text(_ key: String) -> String { String(localized: String.LocalizationValue(key), bundle: .lodyMac) }
}
