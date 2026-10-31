import AppKit
import LodyCore

/// The same two-level model/effort interaction as the iOS composer, in an AppKit popover.
@MainActor
final class MacComposerOptionsController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  var onFast: ((Bool) -> Void)?
  let fast = NSButton()
  var onChange: ((ModelChoice) -> Void)?
  var onResize: ((NSSize) -> Void)?
  let slider = MacEffortSlider()
  private let heading = NSButton()
  private let back = NSButton()
  private let table = MacModelTable()
  private let scroll = NSScrollView()
  private var model = MacComposerModel(mode: .reply)
  private var listing = false

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 296, height: 116))
    view.setAccessibilityIdentifier("composer-options-panel")
    view.setAccessibilityRole(.group)
    view.setAccessibilityElement(true)
    heading.isBordered = false
    heading.bezelStyle = .accessoryBarAction
    heading.target = self
    heading.action = #selector(showModels)
    heading.setAccessibilityIdentifier("composer-model-list")
    fast.isBordered = false
    fast.bezelStyle = .accessoryBarAction
    fast.target = self
    fast.action = #selector(toggleFast)
    fast.setAccessibilityIdentifier("composer-fast")
    fast.setAccessibilityLabel(String(localized: "mac.composer.fast", bundle: .lodyMac))
    back.title = String(localized: "mac.composer.model", bundle: .lodyMac)
    back.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
    back.imagePosition = .imageLeading
    back.isBordered = false
    back.font = .preferredFont(forTextStyle: .headline)
    back.target = self
    back.action = #selector(showOptions)
    slider.target = self
    slider.action = #selector(changeEffort)
    slider.setAccessibilityIdentifier("composer-effort-slider")
    slider.setAccessibilityLabel(String(localized: "mac.composer.effort", bundle: .lodyMac))
    let column = NSTableColumn(identifier: .init("model"))
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = 44
    table.intercellSpacing = .zero
    table.backgroundColor = .clear
    table.style = .plain
    table.delegate = self
    table.dataSource = self
    table.target = self
    table.action = #selector(pickModel)
    table.onConfirm = { [weak self] in self?.pickModel() }
    table.setAccessibilityIdentifier("composer-model-choices")
    scroll.documentView = table
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    for child in [heading, back, slider, scroll, fast] { view.addSubview(child) }
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    let leading: CGFloat = fast.isHidden ? 12 : 48
    heading.frame = NSRect(x: leading, y: view.bounds.height - 64, width: view.bounds.width - leading - 12, height: 56)
    fast.frame = NSRect(x: 4, y: view.bounds.height - 58, width: 40, height: 44)
    slider.frame = NSRect(x: 12, y: 8, width: view.bounds.width - 24, height: 44)
    back.frame = NSRect(x: 16, y: view.bounds.height - 44, width: view.bounds.width - 32, height: 32)
    scroll.frame = NSRect(x: 8, y: 8, width: view.bounds.width - 16, height: view.bounds.height - 56)
  }

  override func viewDidAppear() { super.viewDidAppear(); slider.resume() }
  override func viewWillDisappear() { slider.suspend(); super.viewWillDisappear() }

  func render(_ model: MacComposerModel) {
    self.model = model
    loadViewIfNeeded()
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let title = NSMutableAttributedString(string: model.effortTitle + " ›\n", attributes: [
      .font: NSFont.preferredFont(forTextStyle: .headline), .paragraphStyle: style,
      .foregroundColor: model.choice.effort?.lowercased() == "ultra" ? NSColor.systemPurple : NSColor.controlAccentColor,
    ])
    title.append(NSAttributedString(string: model.modelTitle, attributes: [
      .font: NSFont.preferredFont(forTextStyle: .subheadline), .paragraphStyle: style,
      .foregroundColor: NSColor.secondaryLabelColor,
    ]))
    heading.attributedTitle = title
    heading.setAccessibilityLabel(model.effortTitle + ", " + model.modelTitle)
    let isFast = CreateLogic.fastMode(model.capability, model.choice)?.enabled ?? false
    fast.state = isFast ? .on : .off
    fast.image = NSImage(systemSymbolName: isFast ? "bolt.fill" : "bolt", accessibilityDescription: nil)
    fast.contentTintColor = isFast ? .controlAccentColor : .secondaryLabelColor
    let efforts = model.orderedEfforts
    let index = efforts.firstIndex(of: model.choice.effort ?? "").map { $0 + 1 } ?? 0
    slider.render(value: Double(index) / Double(max(1, efforts.count)), steps: max(1, efforts.count), ultra: model.choice.effort?.lowercased() == "ultra", fast: isFast)
    slider.setAccessibilityValueDescription(model.effortTitle)
    table.reloadData()
    let selected = model.models.firstIndex { $0.id == model.choice.modelId }.map { $0 + 1 } ?? 0
    table.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
    updateVisibility()
  }

  func selectModel(_ id: String) {
    guard id.isEmpty || model.models.contains(where: { $0.id == id }) else { return }
    var choice = model.choice
    guard (choice.modelId ?? "") != id else { showOptions(); return }
    choice.modelId = id
    choice.effort = ""
    onChange?(choice)
    showOptions()
  }

  @objc func toggleFast() {
    guard let mode = CreateLogic.fastMode(model.capability, model.choice) else { return }
    onFast?(!mode.enabled)
  }

  @objc func changeEffort() {
    let efforts = model.orderedEfforts
    guard !efforts.isEmpty else { return }
    let index = min(efforts.count, max(0, Int((slider.doubleValue * Double(efforts.count)).rounded())))
    let effort = index == 0 ? "" : efforts[index - 1]
    guard effort != (model.choice.effort ?? "") else { return }
    var choice = model.choice
    choice.effort = effort
    onChange?(choice)
  }

  @objc private func showModels() { listing = true; updateVisibility(); view.window?.makeFirstResponder(table) }
  @objc private func showOptions() { listing = false; updateVisibility() }
  @objc private func pickModel() {
    let row = table.selectedRow
    guard row >= 0, row <= model.models.count else { return }
    selectModel(row == 0 ? "" : model.models[row - 1].id)
  }

  private func updateVisibility() {
    fast.isHidden = listing || CreateLogic.fastMode(model.capability, model.choice) == nil
    heading.isHidden = listing
    slider.isHidden = listing || model.efforts.isEmpty
    back.isHidden = !listing
    scroll.isHidden = !listing
    var height: CGFloat = model.efforts.isEmpty ? 72 : 116
    if listing { height = min(364, CGFloat(model.models.count + 1) * 44 + 56) }
    preferredContentSize = NSSize(width: 296, height: height)
    onResize?(preferredContentSize)
    view.needsLayout = true
  }

  func numberOfRows(in tableView: NSTableView) -> Int { model.models.count + 1 }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let title = row == 0 ? String(localized: "mac.composer.defaultModel", bundle: .lodyMac) : model.models[row - 1].name
    let label = NSTextField(labelWithString: title)
    label.font = .preferredFont(forTextStyle: .body)
    label.lineBreakMode = .byTruncatingTail
    label.setAccessibilityIdentifier("composer-model-choice-\(row)")
    let cell = NSTableCellView()
    cell.textField = label
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
      label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }
}

@MainActor
private final class MacModelTable: NSTableView {
  var onConfirm: (() -> Void)?
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 36 || event.keyCode == 76 { onConfirm?(); return }
    super.keyDown(with: event)
  }
}
