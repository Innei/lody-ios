import AppKit

@MainActor
final class MacInspectionController: NSViewController {
  var state = MacInspectionState()
  var onState: ((MacInspectionState) -> Void)?
  var onSelect: ((MacInspectionState.Selection) -> Void)?
  var onFiles: ((NSView) -> Void)?
  var onExpand: (() -> Void)?
  var onClose: (() -> Void)?
  let tabs = MacInspectionTabs()
  let body = NSView()
  let status = NSTextField(labelWithString: "")
  private let header = NSStackView()
  private(set) var model: MacInspectionModel?
  private let diff = MacDiffView()
  private let range = NSPopUpButton()
  private let changeBody = NSStackView()
  private var preview: NSView?

  func bind(_ model: MacInspectionModel?) {
    self.model?.changed = nil
    self.model = model
    guard let model else { state = .init(); render(); return }
    model.changed = { [weak self] in self?.renderModel() }
    _ = view
    renderModel()
  }

  override func loadView() {
    view = NSView()
    view.setAccessibilityIdentifier("inspection-panel")
    tabs.select = { [weak self] selection in
      guard let self else { return }
      state.selection = selection; changed(); onSelect?(selection)
    }
    tabs.pin = { [weak self] target in self?.state.pin(target); self?.changed() }
    tabs.close = { [weak self] target in
      guard let self else { return }
      state.close(target); changed(); onSelect?(state.selection)
    }
    let files = action("folder", "mac.inspection.files", "inspection-files") { [weak self] sender in self?.onFiles?(sender) }
    let expand = action("arrow.up.left.and.arrow.down.right", "mac.inspection.expand", "inspection-expand") { [weak self] _ in self?.onExpand?() }
    let close = action("sidebar.right", "mac.inspection.close", "inspection-close") { [weak self] _ in self?.onClose?() }
    header.setViews([tabs, files, expand, close], in: .leading)
    header.spacing = 3; header.edgeInsets = .init(top: 4, left: 8, bottom: 4, right: 8)
    status.font = .systemFont(ofSize: 10); status.textColor = .secondaryLabelColor
    status.lineBreakMode = .byTruncatingMiddle
    for child in [header, body, status] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: view.leadingAnchor), header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), header.heightAnchor.constraint(equalToConstant: 44),
      body.topAnchor.constraint(equalTo: header.bottomAnchor), body.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      body.trailingAnchor.constraint(equalTo: view.trailingAnchor), body.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -4),
      status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10), status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
      status.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4), status.heightAnchor.constraint(equalToConstant: 15),
    ])
    render()
  }
  required init?(coder: NSCoder) { nil }
  init() { super.init(nibName: nil, bundle: nil) }

  func render() { guard isViewLoaded else { return }; tabs.render(state) }
  private func changed() { model?.state = state; render(); onState?(state) }

  func renderModel() {
    guard let model else { return }
    state = model.state; render(); onState?(state)
    onSelect = { [weak model] in model?.select($0) }
    switch state.selection {
    case .changes:
      range.removeAllItems()
      range.addItems(withTitles: [MacInspectionUI.text("mac.inspection.thisTurn"), MacInspectionUI.text("mac.inspection.workspace")])
      range.item(at: 0)?.isEnabled = model.selectedTurn != nil || model.latestTurn != nil
      range.selectItem(at: model.turn == nil ? 1 : 0)
      range.target = self; range.action = #selector(changeRange)
      range.setAccessibilityIdentifier("inspection-range")
      let refresh = MacInspectionUI.button(MacInspectionUI.text("mac.inspection.refresh"), "inspection-refresh") { [weak model] in model?.refresh() }
      let toolbar = NSStackView(views: [range, NSView(), refresh]); toolbar.spacing = 8
      toolbar.edgeInsets = .init(top: 4, left: 10, bottom: 4, right: 10)
      changeBody.arrangedSubviews.forEach { changeBody.removeArrangedSubview($0); $0.removeFromSuperview() }
      changeBody.orientation = .vertical; changeBody.spacing = 0; changeBody.alignment = .leading
      changeBody.addArrangedSubview(toolbar)
      toolbar.widthAnchor.constraint(equalTo: changeBody.widthAnchor).isActive = true
      if model.files.isEmpty {
        let text = model.changesError ?? MacInspectionUI.text(model.changesBusy ? "mac.inspection.loading" : "mac.inspection.noChanges")
        let message = MacInspectionUI.message(text, retry: model.changesError == nil ? nil : { [weak model] in model?.refresh() })
        changeBody.addArrangedSubview(message)
      } else {
        if let error = model.changesError { changeBody.addArrangedSubview(NSTextField(wrappingLabelWithString: error)) }
        changeBody.addArrangedSubview(diff)
        diff.widthAnchor.constraint(equalTo: changeBody.widthAnchor).isActive = true
        diff.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        diff.setContentHuggingPriority(.init(1), for: .vertical)
        diff.render(model)
      }
      display(changeBody)
      status.stringValue = model.turn?.title ?? model.base
    case .document(let target):
      renderDocument(target)
    }
  }

  @objc private func changeRange() {
    guard let model else { return }
    let turn = range.indexOfSelectedItem == 0 ? model.selectedTurn ?? model.latestTurn : nil
    model.showChanges(entry: turn)
  }

  func revealDiff(_ path: String) { diff.reveal(path) }

  private func renderDocument(_ target: MacInspectionTarget) {
    guard let model else { return }
    let load = model.documents[target]
    status.stringValue = target.path
    let message = load?.error ?? MacInspectionUI.text("mac.inspection.loading")
    display(MacInspectionUI.message(message, retry: { [weak model] in model?.loadDocument(target, force: true) }))
  }

  func display(_ content: NSView) {
    _ = view
    if body.subviews.first === content { return }
    body.subviews.forEach { $0.removeFromSuperview() }
    content.translatesAutoresizingMaskIntoConstraints = false
    body.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: body.leadingAnchor), content.trailingAnchor.constraint(equalTo: body.trailingAnchor),
      content.topAnchor.constraint(equalTo: body.topAnchor), content.bottomAnchor.constraint(equalTo: body.bottomAnchor),
    ])
  }

  private func action(_ symbol: String, _ key: String.LocalizationValue, _ id: String, invoke: @escaping (NSView) -> Void) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(), target: nil, action: nil)
    button.isBordered = false; button.bezelStyle = .accessoryBarAction
    button.toolTip = String(localized: key, bundle: .lodyMac); button.setAccessibilityLabel(button.toolTip)
    button.setAccessibilityIdentifier(id)
    let target = MacInspectionAction(invoke)
    button.target = target; button.action = #selector(MacInspectionAction.run(_:))
    actionTargets.append(target)
    button.widthAnchor.constraint(equalToConstant: 28).isActive = true
    return button
  }
  private var actionTargets: [MacInspectionAction] = []
}

@MainActor
private final class MacInspectionAction: NSObject {
  let invoke: (NSView) -> Void
  init(_ invoke: @escaping (NSView) -> Void) { self.invoke = invoke }
  @objc func run(_ sender: NSButton) { invoke(sender) }
}
