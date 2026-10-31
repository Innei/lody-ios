#if DEBUG
import AppKit
import LodyCore
import LodyData

/// Offline design alternatives. The approved production composer is left intact.
@MainActor
enum MacModelPickerStudy {
  static func windows(_ variant: String) -> [NSWindow] {
    if variant == "reference" { return referenceWindows() }
    let windows = MacFixtures.workspaceWindow(sessionId: "s-mac", shell: true)
    guard let window = windows.first, let root = window.contentViewController,
      let composer = descendants(window.contentView).compactMap({ $0 as? MacComposerView }).first else { return windows }
    window.setContentSize(NSSize(width: 1100, height: 720))
    let host = ModelPickerStudyHost(variant: variant, composer: composer)
    root.addChild(host)
    composer.modelPicker.target = host
    composer.modelPicker.action = #selector(ModelPickerStudyHost.show(_:))
    return windows
  }

  /// The approved study now uses the production controller and choice persistence seam.
  private static func referenceWindows() -> [NSWindow] {
    let windows = MacFixtures.workspaceWindow(sessionId: "s-mac", shell: true)
    guard let window = windows.first,
      let composer = controllers(window.contentViewController).compactMap({ $0 as? MacComposerController }).first else { return windows }
    window.setContentSize(NSSize(width: 1100, height: 720))
    let names = ["GPT-6.1 Sol", "GPT-6 Astra", "GPT-6.1 Terra", "GPT-6 Sol", "GPT-6 Luna", "GPT-5.6 Sol", "GPT-5.6 Terra", "GPT-5.6 Luna"]
    let models = names.enumerated().map { CapabilityChoice(id: "reference-\($0.offset)", name: $0.element) }
    let capability = Capability(machineId: "offline", cliType: "fixture", agentType: "reference", models: models,
      reasoningEfforts: ["": ["low", "medium", "high", "xhigh"]],
      configOptions: [ConfigOption(id: "fast", name: "Fast", type: "boolean", currentValue: .bool(false))])
    let choice = ModelChoice(modelId: "reference-1", effort: "medium")
    let state = SessionComposerModel(choice: choice, service: SessionComposerService(options: { _, _ in
      CreationOptions(sessionId: "reference", agents: [], capabilities: [capability])
    }, tier: { _, _ in nil }))
    state.changed = { [weak composer, weak state] in
      guard let state else { return }
      composer?.updateReply(ready: true, capability: state.capability, choice: state.active)
    }
    composer.onReplyChoice = { body in state.change(body) }
    state.load(workspaceId: "offline", projectId: "reference", session: SessionItem(id: "reference", machineId: "offline", cliType: "fixture", agentType: "reference"))
    composer.updateReply(ready: true, capability: capability, choice: choice)
    return windows
  }

  private static func controllers(_ controller: NSViewController?) -> [NSViewController] {
    guard let controller else { return [] }
    return [controller] + controller.children.flatMap { controllers($0) }
  }

  private static func descendants(_ view: NSView?) -> [NSView] {
    guard let view else { return [] }
    return [view] + view.subviews.flatMap { descendants($0) }
  }
}

@MainActor
private final class ModelPickerStudyHost: NSViewController {
  private let popover = NSPopover()

  init(variant: String, composer: MacComposerView) {
    super.init(nibName: nil, bundle: nil)
    popover.behavior = .transient
    let changed: (MacComposerModel) -> Void = { [weak composer] model in
      composer?.modelPicker.title = model.modelTitle + "  " + model.effortTitle
      composer?.modelPicker.setAccessibilityLabel(model.modelTitle + ", " + model.effortTitle)
    }
    let panel = ModelPickerStudyPanel(variant: variant, onChange: changed)
    popover.contentViewController = panel
    panel.onResize = { [weak popover] size in popover?.contentSize = size }
    panel.loadViewIfNeeded()
    popover.contentSize = panel.preferredContentSize
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func loadView() { view = NSView() }

  @objc func show(_ sender: NSButton) {
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
  }
}

@MainActor
private final class ModelPickerStudyPanel: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  var onResize: ((NSSize) -> Void)?
  private let variant: String
  private let onChange: (MacComposerModel) -> Void
  private var model = MacComposerModel(mode: .reply)
  private let table = StudyModelTable()
  private let scroll = NSScrollView()
  private let heading = NSButton()
  private let titleLabel = NSTextField(labelWithString: "Model")
  private let popup = NSPopUpButton()
  private let effort = NSTextField(labelWithString: "High")
  private let slider = MacEffortSlider()
  private let divider = NSBox()
  private var listing = false

  init(variant: String, onChange: @escaping (MacComposerModel) -> Void) {
    self.variant = variant
    self.onChange = onChange
    super.init(nibName: nil, bundle: nil)
    model.replyCapability = MacComposerFixture.capability
    model.replyChoice = ModelChoice(modelId: "opus", effort: "high")
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 296, height: 260))
    view.setAccessibilityIdentifier("model-study-panel")
    view.setAccessibilityRole(.group)
    view.setAccessibilityElement(true)
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.textColor = .secondaryLabelColor
    heading.isBordered = false
    heading.bezelStyle = .accessoryBarAction
    heading.font = .preferredFont(forTextStyle: .headline)
    heading.alignment = .left
    heading.target = self
    heading.action = #selector(toggleListing)
    heading.setAccessibilityIdentifier("model-study-heading")
    let column = NSTableColumn(identifier: .init("model"))
    table.addTableColumn(column)
    table.headerView = nil
    table.rowHeight = 36
    table.intercellSpacing = .zero
    table.style = .plain
    table.backgroundColor = .clear
    table.selectionHighlightStyle = .none
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.action = #selector(pickRow)
    table.onConfirm = { [weak self] in self?.pickRow() }
    table.setAccessibilityIdentifier("model-study-choices")
    scroll.documentView = table
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    popup.addItems(withTitles: ["Default"] + model.models.map(\.name))
    popup.bezelStyle = .rounded
    popup.controlSize = .large
    popup.font = .preferredFont(forTextStyle: .body)
    popup.target = self
    popup.action = #selector(pickPopup)
    popup.setAccessibilityIdentifier("model-study-popup")
    effort.font = .preferredFont(forTextStyle: .body)
    effort.textColor = .secondaryLabelColor
    slider.target = self
    slider.action = #selector(changeEffort)
    slider.setAccessibilityIdentifier("model-study-effort")
    slider.setAccessibilityLabel("Reasoning effort")
    divider.boxType = .separator
    for child in [titleLabel, heading, scroll, popup, effort, slider, divider] { view.addSubview(child) }
    render()
  }

  override func viewDidAppear() { super.viewDidAppear(); slider.resume() }
  override func viewWillDisappear() { slider.suspend(); super.viewWillDisappear() }

  override func viewDidLayout() {
    super.viewDidLayout()
    let width = view.bounds.width
    let height = view.bounds.height
    titleLabel.frame = NSRect(x: 16, y: height - 36, width: width - 32, height: 24)
    heading.frame = NSRect(x: 12, y: height - 44, width: width - 24, height: 32)
    popup.frame = NSRect(x: 12, y: height - 80, width: width - 24, height: 36)
    scroll.frame = NSRect(x: 8, y: height - 152, width: width - 16, height: 108)
    divider.frame = NSRect(x: 16, y: 96, width: width - 32, height: 1)
    effort.frame = NSRect(x: 16, y: 56, width: width - 32, height: 24)
    slider.frame = NSRect(x: 12, y: 8, width: width - 24, height: 44)
    if variant == "b", listing {
      scroll.frame = NSRect(x: 8, y: 8, width: width - 16, height: 108)
    }
  }

  private func render() {
    let inline = variant == "a"
    let nativePopup = variant == "c"
    titleLabel.isHidden = !inline && !nativePopup
    heading.isHidden = inline || nativePopup
    scroll.isHidden = nativePopup || (!inline && !listing)
    popup.isHidden = !nativePopup
    divider.isHidden = !inline || model.efforts.isEmpty
    effort.isHidden = listing || model.efforts.isEmpty
    slider.isHidden = effort.isHidden
    heading.title = listing ? "Model" : model.modelTitle
    heading.image = NSImage(systemSymbolName: listing ? "chevron.left" : "chevron.right", accessibilityDescription: nil)
    heading.imagePosition = listing ? .imageLeading : .imageTrailing
    heading.symbolConfiguration = .init(pointSize: 10, weight: .medium)
    effort.stringValue = "Reasoning effort · " + model.effortTitle
    let index = model.orderedEfforts.firstIndex(of: model.choice.effort ?? "").map { $0 + 1 } ?? 0
    slider.render(value: Double(index) / Double(max(1, model.orderedEfforts.count)), steps: max(1, model.orderedEfforts.count), ultra: model.choice.effort == "ultra", fast: false)
    slider.setAccessibilityValueDescription(model.effortTitle)
    popup.selectItem(at: selectedRow)
    table.reloadData()
    table.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
    var height: CGFloat = 260
    if variant == "b" { height = listing ? 160 : 144 }
    if nativePopup { height = 184 }
    if model.efforts.isEmpty && !listing { height -= 88 }
    preferredContentSize = NSSize(width: 296, height: height)
    onResize?(preferredContentSize)
    view.needsLayout = true
  }

  private var selectedRow: Int {
    model.models.firstIndex { $0.id == model.choice.modelId }.map { $0 + 1 } ?? 0
  }

  @objc private func toggleListing() { listing.toggle(); render() }
  @objc private func pickRow() { select(table.selectedRow) }
  @objc private func pickPopup() { select(popup.indexOfSelectedItem) }

  private func select(_ row: Int) {
    guard row >= 0, row <= model.models.count else { return }
    let id = row == 0 ? "" : model.models[row - 1].id
    if id != (model.replyChoice.modelId ?? "") {
      model.replyChoice.modelId = id
      model.replyChoice.effort = ""
    }
    listing = false
    render()
    onChange(model)
  }

  @objc private func changeEffort() {
    let efforts = model.orderedEfforts
    let index = min(efforts.count, max(0, Int((slider.doubleValue * Double(efforts.count)).rounded())))
    model.replyChoice.effort = index == 0 ? "" : efforts[index - 1]
    render()
    onChange(model)
  }

  func numberOfRows(in tableView: NSTableView) -> Int { model.models.count + 1 }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = NSTableCellView()
    let name = row == 0 ? "Default" : model.models[row - 1].name
    let label = NSTextField(labelWithString: name)
    label.font = .preferredFont(forTextStyle: .body)
    label.frame = NSRect(x: 8, y: 8, width: 224, height: 20)
    cell.addSubview(label)
    cell.textField = label
    let check = NSImageView(image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil) ?? NSImage())
    check.contentTintColor = .lodyAccent
    check.frame = NSRect(x: 244, y: 10, width: 16, height: 16)
    check.isHidden = row != selectedRow
    cell.addSubview(check)
    return cell
  }
}

@MainActor
private final class StudyModelTable: NSTableView {
  var onConfirm: (() -> Void)?
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 36 || event.keyCode == 76 { onConfirm?(); return }
    super.keyDown(with: event)
  }
}

#endif
