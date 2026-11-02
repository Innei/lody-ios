import AppKit
import LodyData

@MainActor
final class MacInspectionController: NSViewController, NSPopoverDelegate, NSSearchFieldDelegate {
  var state = MacInspectionState()
  var onState: ((MacInspectionState) -> Void)?
  var onSelect: ((MacInspectionState.Selection) -> Void)?
  var onFiles: ((NSView) -> Void)?
  var onExpand: (() -> Void)?
  var onClose: (() -> Void)?
  var repositoryName = "" { didSet { repository.stringValue = repositoryName; repository.toolTip = repositoryName } }
  let tabs = MacInspectionTabs()
  let body = NSView()
  let status = NSTextField(labelWithString: "")
  let chrome = MacInspectionSurface(frame: NSRect(x: 0, y: 0, width: 640, height: 52))
  private(set) var model: MacInspectionModel?
  private let diff = MacDiffView()
  private let range = NSPopUpButton()
  private let repository = MacInspectionUI.label("")
  private let repositoryRow = NSStackView()
  private let totals = NSStackView()
  private let changeBody = NSView()
  private let toolbar = MacInspectionSurface()
  private let toolbarRow = NSStackView()
  private let search = NSSearchField()
  private var searchVisible = false
  private var searchHeight: NSLayoutConstraint?
  private var preview: NSView?
  private var fileBrowser: NSPopover?
  private weak var filesAnchor: NSView?
  private var errorView: NSView?

  func bind(_ model: MacInspectionModel?) {
    (preview as? MacFilePreviewView)?.saveReading()
    discardPreview(); fileBrowser?.close()
    if isViewLoaded { body.subviews.forEach { $0.removeFromSuperview() } }
    self.model?.changed = nil; self.model = model
    guard let model else { state = .init(); render(); return }
    model.changed = { [weak self] in self?.renderModel() }
    _ = view; renderModel()
    onFiles = { [weak self] sender in self?.showFiles(sender) }
  }

  override func loadView() {
    let root = MacInspectionSurface(); root.leadingRule = true; view = root
    view.setAccessibilityIdentifier("inspection-panel")
    tabs.select = { [weak self] selection in
      guard let self else { return }; state.selection = selection; changed(); onSelect?(selection)
    }
    tabs.pin = { [weak self] target in self?.state.pin(target); self?.changed() }
    tabs.close = { [weak self] target in
      guard let self else { return }
      if let model { model.closeDocument(target); model.select(model.state.selection); return }
      state.close(target); changed(); onSelect?(state.selection)
    }
    chrome.fill = .windowBackgroundColor; chrome.leadingRule = true; chrome.bottomRule = true
    chrome.setAccessibilityIdentifier("inspection-chrome")
    let expand = icon("arrow.up.left.and.arrow.down.right", "mac.inspection.expand", "inspection-expand") { [weak self] _ in self?.onExpand?() }
    let close = icon("sidebar.right", "mac.inspection.close", "inspection-close") { [weak self] _ in self?.onClose?() }
    let add = icon("plus", "mac.inspection.files", "inspection-new-tab") { [weak self] sender in self?.showFiles(sender) }
    let header = NSStackView(views: [tabs, add, expand, close]); header.spacing = 4
    header.translatesAutoresizingMaskIntoConstraints = false; chrome.addSubview(header)
    tabs.setContentHuggingPriority(.defaultLow, for: .horizontal)
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: chrome.leadingAnchor, constant: 8), header.trailingAnchor.constraint(equalTo: chrome.trailingAnchor, constant: -8),
      header.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 6), header.bottomAnchor.constraint(equalTo: chrome.bottomAnchor, constant: -6),
    ])
    let footer = MacInspectionSurface(); footer.fill = .windowBackgroundColor; footer.topRule = true
    status.font = .systemFont(ofSize: 10); status.textColor = .secondaryLabelColor; status.lineBreakMode = .byTruncatingMiddle
    status.translatesAutoresizingMaskIntoConstraints = false; footer.addSubview(status)
    for child in [body, footer] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
    NSLayoutConstraint.activate([
      body.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), body.leadingAnchor.constraint(equalTo: view.leadingAnchor), body.trailingAnchor.constraint(equalTo: view.trailingAnchor), body.bottomAnchor.constraint(equalTo: footer.topAnchor),
      footer.heightAnchor.constraint(equalToConstant: 27), footer.bottomAnchor.constraint(equalTo: view.bottomAnchor), footer.leadingAnchor.constraint(equalTo: view.leadingAnchor), footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      status.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 13), status.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -13), status.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
    ])
    configureChanges(); render()
  }
  required init?(coder: NSCoder) { nil }
  init() { super.init(nibName: nil, bundle: nil) }
  override func viewDidLayout() {
    super.viewDidLayout()
    repositoryRow.isHidden = view.bounds.width < 480
    if let preview = preview as? MacFilePreviewView { preview.needsLayout = true }
  }

  private func configureChanges() {
    toolbar.bottomRule = true
    let folder = NSImageView(image: NSImage(systemSymbolName: "folder", accessibilityDescription: nil) ?? NSImage()); folder.contentTintColor = .secondaryLabelColor
    folder.widthAnchor.constraint(equalToConstant: 14).isActive = true
    repositoryRow.setViews([folder, repository], in: .leading); repositoryRow.spacing = 6
    repository.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    repository.widthAnchor.constraint(lessThanOrEqualToConstant: 120).isActive = true
    range.addItems(withTitles: [MacInspectionUI.text("mac.inspection.thisTurn"), MacInspectionUI.text("mac.inspection.workspace")])
    range.target = self; range.action = #selector(changeRange); range.font = .systemFont(ofSize: 12)
    range.isBordered = false; range.setAccessibilityIdentifier("inspection-range")
    (range.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
    range.widthAnchor.constraint(equalToConstant: 112).isActive = true
    let chevron = NSImageView(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) ?? NSImage()); chevron.symbolConfiguration = .init(pointSize: 9, weight: .medium)
    chevron.widthAnchor.constraint(equalToConstant: 10).isActive = true
    let picker = NSStackView(views: [range, chevron]); picker.spacing = 0
    let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
    totals.spacing = 7
    let find = icon("magnifyingglass", "mac.inspection.find", "inspection-change-search") { [weak self] _ in self?.toggleSearch() }
    let files = icon("folder", "mac.inspection.files", "inspection-files") { [weak self] sender in self?.showFiles(sender) }
    let more = icon("ellipsis", "mac.inspection.options", "inspection-options") { [weak self] sender in self?.showOptions(sender) }
    toolbarRow.setViews([repositoryRow, picker, totals, spacer, find, files, more], in: .leading)
    toolbarRow.spacing = 8; toolbarRow.translatesAutoresizingMaskIntoConstraints = false; toolbar.addSubview(toolbarRow)
    search.setAccessibilityIdentifier("inspection-change-filter"); search.placeholderString = MacInspectionUI.text("mac.inspection.filterChanges"); search.delegate = self
    search.isHidden = true; search.controlSize = .small
    for child in [toolbar, search, diff] { child.translatesAutoresizingMaskIntoConstraints = false; changeBody.addSubview(child) }
    let height = search.heightAnchor.constraint(equalToConstant: 0); height.isActive = true; searchHeight = height
    NSLayoutConstraint.activate([
      toolbar.topAnchor.constraint(equalTo: changeBody.topAnchor), toolbar.leadingAnchor.constraint(equalTo: changeBody.leadingAnchor), toolbar.trailingAnchor.constraint(equalTo: changeBody.trailingAnchor), toolbar.heightAnchor.constraint(equalToConstant: 45),
      toolbarRow.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 14), toolbarRow.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8), toolbarRow.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
      search.topAnchor.constraint(equalTo: toolbar.bottomAnchor), search.leadingAnchor.constraint(equalTo: changeBody.leadingAnchor, constant: 12), search.trailingAnchor.constraint(equalTo: changeBody.trailingAnchor, constant: -12),
      diff.topAnchor.constraint(equalTo: search.bottomAnchor), diff.leadingAnchor.constraint(equalTo: changeBody.leadingAnchor), diff.trailingAnchor.constraint(equalTo: changeBody.trailingAnchor), diff.bottomAnchor.constraint(equalTo: changeBody.bottomAnchor),
    ])
  }

  func render() { guard isViewLoaded else { return }; tabs.render(state) }
  private func changed() { model?.updateState(state); render(); onState?(state) }
  func renderModel() {
    guard let model else { return }
    (preview as? MacFilePreviewView)?.saveReading()
    if model.isSuspended { fileBrowser?.close(); fileBrowser = nil; discardPreview() }
    if let pane = preview as? MacFilePreviewView, !model.state.tabs.contains(where: { $0.target == pane.target }) { discardPreview() }
    state = model.state; render(); onState?(state)
    onSelect = { [weak model] in model?.select($0) }
    switch state.selection {
    case .changes:
      range.item(at: 0)?.isEnabled = model.selectedTurn != nil || model.latestTurn != nil
      range.selectItem(at: model.turn == nil ? 1 : 0)
      range.toolTip = range.titleOfSelectedItem
      totals.arrangedSubviews.forEach { totals.removeArrangedSubview($0); $0.removeFromSuperview() }
      let additions = model.files.compactMap(\.add), deletions = model.files.compactMap(\.del)
      if !additions.isEmpty { totals.addArrangedSubview(MacInspectionUI.label("+\(additions.reduce(0, +))", color: .systemGreen)) }
      if !deletions.isEmpty { totals.addArrangedSubview(MacInspectionUI.label("−\(deletions.reduce(0, +))", color: .systemRed)) }
      errorView?.removeFromSuperview(); errorView = nil
      diff.isHidden = model.files.isEmpty
      if model.files.isEmpty {
        let text = model.changesError ?? MacInspectionUI.text(model.changesBusy || model.isSuspended ? "mac.inspection.loading" : "mac.inspection.noChanges")
        let message = MacInspectionUI.message(text, retry: model.changesError == nil ? nil : { [weak model] in model?.refresh() })
        message.translatesAutoresizingMaskIntoConstraints = false; changeBody.addSubview(message); errorView = message
        NSLayoutConstraint.activate([message.centerXAnchor.constraint(equalTo: changeBody.centerXAnchor), message.centerYAnchor.constraint(equalTo: changeBody.centerYAnchor), message.widthAnchor.constraint(lessThanOrEqualTo: changeBody.widthAnchor, constant: -40)])
      }
      diff.render(model); display(changeBody)
      if let path = model.revealPath { diff.reveal(path); model.revealPath = nil }
      let count = String.localizedStringWithFormat(String(localized: "native.chat.transcript.fileCount", bundle: .lodyData), model.files.count)
      status.stringValue = [count, model.turn?.title ?? model.base, model.changesError].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    case .document(let target): renderDocument(target)
    }
  }
  @objc private func changeRange() {
    guard let model else { return }
    model.showChanges(entry: range.indexOfSelectedItem == 0 ? model.selectedTurn ?? model.latestTurn : nil)
  }
  func revealDiff(_ path: String) { diff.reveal(path) }
  private func toggleSearch() {
    searchVisible.toggle(); search.isHidden = !searchVisible; searchHeight?.constant = searchVisible ? 34 : 0
    if searchVisible { view.window?.makeFirstResponder(search) }
    else { search.stringValue = ""; diff.filter = "" }
  }
  func controlTextDidChange(_ obj: Notification) { diff.filter = search.stringValue }
  override func cancelOperation(_ sender: Any?) { if searchVisible { toggleSearch() } else { super.cancelOperation(sender) } }

  private func renderDocument(_ target: MacInspectionTarget) {
    guard let model else { return }
    let load = model.documents[target]
    if let content = load?.value {
      let pane: MacFilePreviewView
      if let existing = preview as? MacFilePreviewView, existing.target == target, existing.content == content { pane = existing }
      else {
        discardPreview(); pane = MacFilePreviewView(target: target, content: content, model: model)
        pane.onFiles = { [weak self] sender in self?.showFiles(sender) }; preview = pane
      }
      display(pane)
      status.stringValue = [pane.contentDescription, MacInspectionUI.text("mac.inspection.currentFile")].filter { !$0.isEmpty }.joined(separator: " · ")
      if let error = load?.error { status.stringValue = MacInspectionUI.text("mac.inspection.stale") + " · " + error }
    } else {
      status.stringValue = target.path
      display(MacInspectionUI.message(load?.error ?? MacInspectionUI.text("mac.inspection.loading"), retry: load?.error == nil ? nil : { [weak model] in model?.loadDocument(target, force: true) }))
    }
  }
  private func showFiles(_ sender: NSView) {
    guard let model else { return }
    if fileBrowser?.isShown == true { fileBrowser?.close(); return }
    let popover = NSPopover(); popover.behavior = .transient
    let browser = MacFileBrowserController(model: model)
    browser.onPick = { [weak popover, weak model] target in popover?.close(); model?.show(target) }
    popover.contentViewController = browser; popover.contentSize = NSSize(width: 350, height: 440)
    popover.delegate = self; filesAnchor = sender; fileBrowser = popover
    popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
  }
  private func showOptions(_ sender: NSView) {
    let menu = NSMenu()
    for (key, action) in [(String.LocalizationValue("mac.inspection.expandAll"), #selector(expandAll)), ("mac.inspection.collapseAll", #selector(collapseAll)), ("mac.inspection.refresh", #selector(refresh))] {
      let item = NSMenuItem(title: MacInspectionUI.text(key), action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
    }
    menu.popUp(positioning: nil, at: .init(x: 0, y: sender.bounds.maxY), in: sender)
  }
  @objc private func expandAll() { guard let model else { return }; for file in model.files where !model.expanded.contains(file.path) { model.toggleDiff(file.path) } }
  @objc private func collapseAll() { guard let model else { return }; for file in model.files where model.expanded.contains(file.path) { model.toggleDiff(file.path) } }
  @objc private func refresh() { model?.refresh() }
  func findInFile() { (preview as? MacFilePreviewView)?.find() }
  private func discardPreview() { (preview as? MacFilePreviewView)?.releasePreview(); preview = nil }
  func popoverDidClose(_ notification: Notification) { if let anchor = filesAnchor { anchor.window?.makeFirstResponder(anchor) } }
  func display(_ content: NSView) {
    _ = view
    if body.subviews.first === content { return }
    body.subviews.forEach { $0.removeFromSuperview() }
    content.translatesAutoresizingMaskIntoConstraints = false; body.addSubview(content)
    NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: body.leadingAnchor), content.trailingAnchor.constraint(equalTo: body.trailingAnchor), content.topAnchor.constraint(equalTo: body.topAnchor), content.bottomAnchor.constraint(equalTo: body.bottomAnchor)])
  }
  private func icon(_ symbol: String, _ key: String.LocalizationValue, _ id: String, _ invoke: @escaping (NSView) -> Void) -> NSButton {
    MacInspectionUI.icon(symbol, title: MacInspectionUI.text(key), id: id, invoke)
  }
}
