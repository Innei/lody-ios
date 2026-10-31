import AppKit
import LodyCore

/// Native browsing selection and hover are separate from the committed model check.
@MainActor
final class MacModelChoicesView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
  var onPick: ((String) -> Void)?
  private let choices = MacModelTable()
  private var models: [CapabilityChoice] = []
  private var selectedId = ""
  private var hasRendered = false
  var contentHeight: CGFloat { 56 + CGFloat(models.count) * 32 }

  override init(frame: NSRect) {
    super.init(frame: frame)
    choices.addTableColumn(NSTableColumn(identifier: .init("model")))
    choices.headerView = nil
    choices.rowHeight = 32
    choices.intercellSpacing = .zero
    choices.style = .plain
    choices.backgroundColor = .clear
    choices.dataSource = self
    choices.delegate = self
    choices.target = self
    choices.action = #selector(pick)
    choices.onConfirm = { [weak self] in self?.pick() }
    choices.setAccessibilityIdentifier("composer-model-choices")
    documentView = choices
    drawsBackground = false
    hasVerticalScroller = true
    autohidesScrollers = true
  }
  required init?(coder: NSCoder) { nil }

  func render(models: [CapabilityChoice], selectedId: String?) {
    let id = selectedId ?? ""
    guard !hasRendered || self.models != models || self.selectedId != id else { return }
    hasRendered = true
    self.models = models
    self.selectedId = id
    choices.reloadData()
    let row = committedRow ?? 0
    choices.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
  }

  func focus() {
    choices.usingKeyboard = false
    choices.selectRowIndexes(IndexSet(integer: committedRow ?? 0), byExtendingSelection: false)
    window?.makeFirstResponder(choices)
    choices.scrollRowToVisible(choices.selectedRow)
  }

  private var committedRow: Int? {
    if selectedId.isEmpty { return 0 }
    return models.firstIndex { $0.id == selectedId }.map { $0 + 1 }
  }

  @objc private func pick() {
    let row = choices.selectedRow
    guard row >= 0, row <= models.count else { return }
    onPick?(row == 0 ? "" : models[row - 1].id)
  }

  func numberOfRows(in tableView: NSTableView) -> Int { models.count + 1 }
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { row == 0 ? 56 : 32 }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    let view = MacModelRow()
    view.table = choices
    return view
  }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = NSTableCellView()
    let title = row == 0 ? String(localized: "mac.composer.automaticModel", bundle: .lodyMac) : models[row - 1].name
    let label = NSTextField(labelWithString: title)
    label.font = .preferredFont(forTextStyle: .body)
    label.lineBreakMode = .byTruncatingTail
    label.setAccessibilityIdentifier("composer-model-choice-\(row)")
    let check = NSImageView(image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) ?? NSImage())
    check.contentTintColor = .labelColor
    check.isHidden = row != committedRow
    cell.textField = label
    for child in [label, check] { child.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(child) }
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
      label.trailingAnchor.constraint(lessThanOrEqualTo: check.leadingAnchor, constant: -8),
      label.heightAnchor.constraint(equalToConstant: 20),
      check.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
      check.widthAnchor.constraint(equalToConstant: 16), check.heightAnchor.constraint(equalToConstant: 16),
      check.centerYAnchor.constraint(equalTo: label.centerYAnchor),
    ])
    if row == 0 {
      let detail = NSTextField(labelWithString: String(localized: "mac.composer.modelDefaultDescription", bundle: .lodyMac))
      detail.font = .preferredFont(forTextStyle: .subheadline)
      detail.textColor = .secondaryLabelColor
      detail.lineBreakMode = .byTruncatingTail
      detail.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(detail)
      NSLayoutConstraint.activate([
        label.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
        detail.leadingAnchor.constraint(equalTo: label.leadingAnchor),
        detail.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
        detail.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 2),
        detail.heightAnchor.constraint(equalToConstant: 20),
      ])
    } else {
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
    }
    return cell
  }
}

@MainActor
private final class MacModelTable: NSTableView {
  var onConfirm: (() -> Void)?
  var usingKeyboard = false { didSet { needsDisplay = true; subviews.forEach { $0.needsDisplay = true } } }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 36 || event.keyCode == 76 { onConfirm?(); return }
    usingKeyboard = true
    super.keyDown(with: event)
  }
}

@MainActor
private final class MacModelRow: NSTableRowView {
  override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
  weak var table: MacModelTable?
  private var hovered = false
  private var tracking: NSTrackingArea?
  override func updateTrackingAreas() {
    if let tracking { removeTrackingArea(tracking) }
    tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    if let tracking { addTrackingArea(tracking) }
    super.updateTrackingAreas()
  }
  override func mouseEntered(with event: NSEvent) { hovered = true; table?.usingKeyboard = false; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
  override func drawBackground(in dirtyRect: NSRect) { if hovered { highlight() } }
  override func drawSelection(in dirtyRect: NSRect) { if table?.usingKeyboard == true { highlight() } }
  private func highlight() {
    NSColor.unemphasizedSelectedContentBackgroundColor.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 8, yRadius: 8).fill()
  }
}
