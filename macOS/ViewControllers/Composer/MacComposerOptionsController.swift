import AppKit
import LodyCore

/// The same two-level model/effort interaction as the iOS composer, in an AppKit popover.
@MainActor
final class MacComposerOptionsController: NSViewController {
  var onFast: ((Bool) -> Void)?
  let fast = NSButton()
  var onChange: ((ModelChoice) -> Void)?
  var onResize: ((NSSize) -> Void)?
  let slider = MacEffortSlider()
  private let heading = NSButton()
  private let effort = NSTextField(labelWithString: "")
  private let reset = NSButton()
  private let listTitle = NSTextField(labelWithString: "")
  private let back = NSButton()
  private let choices = MacModelChoicesView()
  private var model = MacComposerModel(mode: .reply)
  private var listing = false

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 296, height: 116))
    view.setAccessibilityIdentifier("composer-options-panel")
    view.setAccessibilityRole(.group)
    view.setAccessibilityElement(true)
    heading.isBordered = false
    heading.bezelStyle = .accessoryBarAction
    heading.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
    heading.imagePosition = .imageTrailing
    heading.symbolConfiguration = .init(pointSize: 10, weight: .medium)
    heading.target = self
    heading.action = #selector(showModels)
    heading.setAccessibilityIdentifier("composer-model-list")
    fast.isBordered = false
    fast.bezelStyle = .accessoryBarAction
    fast.setButtonType(.toggle)
    fast.target = self
    fast.action = #selector(toggleFast)
    fast.setAccessibilityIdentifier("composer-fast")
    fast.setAccessibilityLabel(String(localized: "mac.composer.fast", bundle: .lodyMac))
    fast.toolTip = String(localized: "mac.composer.fast", bundle: .lodyMac)
    effort.font = .preferredFont(forTextStyle: .headline)
    effort.alignment = .center
    reset.isBordered = false
    reset.bezelStyle = .accessoryBarAction
    reset.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
    reset.contentTintColor = .secondaryLabelColor
    reset.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    reset.target = self
    reset.action = #selector(resetOptions)
    reset.toolTip = String(localized: "mac.composer.resetModelOptions", bundle: .lodyMac)
    reset.setAccessibilityLabel(reset.toolTip)
    reset.setAccessibilityIdentifier("composer-options-reset")
    listTitle.stringValue = String(localized: "mac.composer.selectModel", bundle: .lodyMac)
    listTitle.font = .preferredFont(forTextStyle: .body)
    listTitle.textColor = .secondaryLabelColor
    back.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
    back.isBordered = false
    back.contentTintColor = .secondaryLabelColor
    back.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    back.setAccessibilityLabel(String(localized: "mac.composer.backToEffort", bundle: .lodyMac))
    back.setAccessibilityIdentifier("composer-options-back")
    back.target = self
    back.action = #selector(showOptions)
    slider.target = self
    slider.action = #selector(changeEffort)
    slider.setAccessibilityIdentifier("composer-effort-slider")
    slider.setAccessibilityLabel(String(localized: "mac.composer.effort", bundle: .lodyMac))
    choices.onPick = { [weak self] in self?.selectModel($0) }
    for child in [heading, effort, back, listTitle, slider, choices, fast, reset] { view.addSubview(child) }
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    let width = view.bounds.width, height = view.bounds.height
    let headingWidth = min(width - 88, heading.fittingSize.width)
    heading.frame = NSRect(x: (width - headingWidth) / 2, y: height - 64, width: headingWidth, height: 24)
    effort.frame = NSRect(x: 44, y: height - 36, width: width - 88, height: 24)
    fast.frame = NSRect(x: 8, y: height - 40, width: 32, height: 32)
    reset.frame = NSRect(x: width - 40, y: height - 40, width: 32, height: 32)
    slider.frame = NSRect(x: 12, y: 8, width: width - 24, height: 44)
    back.frame = NSRect(x: 8, y: height - 40, width: 28, height: 32)
    listTitle.frame = NSRect(x: 40, y: height - 36, width: width - 56, height: 24)
    choices.frame = NSRect(x: 4, y: 8, width: width - 8, height: height - 52)
  }

  override func viewDidAppear() { super.viewDidAppear(); slider.resume() }
  override func viewWillDisappear() { slider.suspend(); super.viewWillDisappear() }

  func render(_ model: MacComposerModel) {
    self.model = model
    loadViewIfNeeded()
    heading.attributedTitle = NSAttributedString(string: model.modelTitle, attributes: [
      .font: NSFont.preferredFont(forTextStyle: .body),
      .foregroundColor: NSColor.secondaryLabelColor,
    ])
    heading.setAccessibilityLabel(model.effortTitle + ", " + model.modelTitle)
    effort.stringValue = model.effortTitle
    effort.textColor = model.choice.effort?.lowercased() == "ultra" ? .systemPurple : .lodyAccent
    let isFast = CreateLogic.fastMode(model.capability, model.choice)?.enabled ?? false
    fast.state = isFast ? .on : .off
    fast.image = NSImage(systemSymbolName: isFast ? "bolt.fill" : "bolt", accessibilityDescription: nil)
    fast.contentTintColor = isFast ? .controlAccentColor : .secondaryLabelColor
    fast.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    let fastChanged = CreateLogic.fastMode(model.capability, model.choice)?.enabled != CreateLogic.fastMode(model.capability, ModelChoice())?.enabled
    reset.isEnabled = model.choice.modelId?.isEmpty == false || model.choice.effort?.isEmpty == false || fastChanged
    let efforts = model.orderedEfforts
    let index = efforts.firstIndex(of: model.choice.effort ?? "").map { $0 + 1 } ?? 0
    slider.render(value: Double(index) / Double(max(1, efforts.count)), steps: max(1, efforts.count), ultra: model.choice.effort?.lowercased() == "ultra", fast: isFast)
    slider.setAccessibilityValueDescription(model.effortTitle)
    choices.render(models: model.models, selectedId: model.choice.modelId)
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

  @objc private func resetOptions() {
    var choice = model.choice
    choice.modelId = ""
    choice.effort = ""
    if let fast = CreateLogic.fastMode(model.capability, model.choice) {
      choice.configOptionValues?.removeValue(forKey: fast.id)
    }
    onChange?(choice)
  }

  @objc private func showModels() { listing = true; updateVisibility(); choices.focus() }
  @objc private func showOptions() { listing = false; updateVisibility() }

  private func updateVisibility() {
    fast.isHidden = listing || CreateLogic.fastMode(model.capability, model.choice) == nil
    heading.isHidden = listing
    effort.isHidden = listing
    reset.isHidden = listing
    slider.isHidden = listing || model.efforts.isEmpty
    back.isHidden = !listing
    listTitle.isHidden = !listing
    choices.isHidden = !listing
    var height: CGFloat = model.efforts.isEmpty ? 72 : 116
    if listing { height = min(364, choices.contentHeight + 52) }
    preferredContentSize = NSSize(width: 296, height: height)
    onResize?(preferredContentSize)
    view.needsLayout = true
  }
}
