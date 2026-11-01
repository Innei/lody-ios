import AppKit
import LodyData

@MainActor
final class MacPaletteController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
  var onPick: ((MacPaletteModel.Destination) -> Void)?
  var onClose: (() -> Void)?
  var onResize: ((NSSize) -> Void)?
  private let mode: MacPaletteModel.Mode
  private var state: SessionListState
  private var scope: MacPaletteModel.Scope = .all
  private var machineId = ""
  private let search = NSSearchField()
  private let clearQuery = NSButton()
  private let filter = NSPopUpButton()
  private let table = MacPaletteTable()
  private let scroll = NSScrollView()
  private let primary = MacKeycapButton(title: "", key: .returnKey)
  private let empty = NSStackView()
  private let emptyTitle = NSTextField(labelWithString: "")
  private var rows: [(heading: String, item: MacPaletteModel.Item?)] = []
  private var updating = false

  init(state: SessionListState, mode: MacPaletteModel.Mode) {
    self.state = state
    self.mode = mode
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { nil }

  override func loadView() {
    let root = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
    root.material = .popover
    root.blendingMode = .behindWindow
    root.state = .active
    root.wantsLayer = true
    root.layer?.cornerRadius = 20
    root.layer?.masksToBounds = true
    let mask = NSImage(size: NSSize(width: 41, height: 41), flipped: false) { rect in
      NSColor.white.setFill()
      NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20).fill()
      return true
    }
    mask.capInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    mask.resizingMode = .stretch
    root.maskImage = mask
    root.setAccessibilityIdentifier("palette-content")
    let body = NSView()
    body.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(body)
    NSLayoutConstraint.activate([
      body.leadingAnchor.constraint(equalTo: root.leadingAnchor), body.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      body.topAnchor.constraint(equalTo: root.topAnchor), body.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    search.placeholderString = String(localized: "mac.palette.search", bundle: .lodyMac)
    if mode == .projects { search.placeholderString = String(localized: "mac.palette.searchProjects", bundle: .lodyMac) }
    search.font = .systemFont(ofSize: 19)
    search.isBezeled = false
    search.isBordered = false
    search.drawsBackground = false
    search.focusRingType = .none
    (search.cell as? NSSearchFieldCell)?.searchButtonCell = nil
    (search.cell as? NSSearchFieldCell)?.cancelButtonCell = nil
    search.sendsSearchStringImmediately = true
    search.delegate = self
    search.setAccessibilityIdentifier("palette-search")
    search.setAccessibilityLabel(search.placeholderString)
    configure(clearQuery, #selector(clearSearch), "palette-search-clear")
    clearQuery.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
    clearQuery.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    clearQuery.contentTintColor = .secondaryLabelColor
    clearQuery.setAccessibilityLabel(String(localized: "mac.sidebar.clearSearch", bundle: .lodyMac))
    filter.isBordered = false
    filter.font = .preferredFont(forTextStyle: .body)
    filter.setContentHuggingPriority(.required, for: .horizontal)
    filter.target = self
    filter.action = #selector(filterChanged)
    filter.setAccessibilityIdentifier("palette-filter")
    let back = NSButton(image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(cancel))
    back.isBordered = false
    back.symbolConfiguration = .init(pointSize: 18, weight: .regular)
    back.isHidden = mode == .search
    back.setAccessibilityLabel(String(localized: "mac.palette.back", bundle: .lodyMac))
    back.setAccessibilityIdentifier("palette-back")
    let searchMark = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage())
    searchMark.contentTintColor = .secondaryLabelColor
    searchMark.symbolConfiguration = .init(pointSize: 18, weight: .regular)
    searchMark.isHidden = mode == .projects
    searchMark.setAccessibilityElement(false)
    let header = NSStackView(views: [back, searchMark, search, filter, clearQuery])
    header.spacing = 12
    header.alignment = .centerY
    header.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    let close = MacKeycapButton(title: mode == .search ? String(localized: "mac.palette.modeSearch", bundle: .lodyMac) : String(localized: "mac.palette.modeProjects", bundle: .lodyMac), key: .escape)
    configure(close, #selector(cancel), "palette-close")
    close.setAccessibilityLabel(String(localized: "mac.palette.close", bundle: .lodyMac))
    configure(primary, #selector(confirm), "palette-primary")
    let footer = NSStackView(views: [capsule([close]), NSView(), capsule([primary])])
    footer.distribution = .fill
    footer.alignment = .centerY
    footer.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
    table.addTableColumn(NSTableColumn(identifier: .init("result")))
    table.headerView = nil
    table.style = .plain
    table.rowHeight = 36
    table.intercellSpacing = .zero
    table.backgroundColor = .clear
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.doubleAction = #selector(confirm)
    table.setAccessibilityIdentifier("palette-results")
    table.onConfirm = { [weak self] in self?.confirm() }
    table.onMove = { [weak self] step in self?.move(step) }
    table.onCancel = { [weak self] in self?.cancel() }
    scroll.documentView = table
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    empty.orientation = .vertical
    empty.spacing = 8
    empty.alignment = .centerX
    emptyTitle.font = .systemFont(ofSize: 14, weight: .medium)
    emptyTitle.lineBreakMode = .byTruncatingMiddle
    emptyTitle.setAccessibilityIdentifier("palette-empty")
    let hint = NSTextField(labelWithString: String(localized: "mac.palette.emptyHint", bundle: .lodyMac))
    if mode == .projects { hint.stringValue = String(localized: "mac.palette.emptyProjectHint", bundle: .lodyMac) }
    hint.font = .preferredFont(forTextStyle: .caption1)
    hint.textColor = .secondaryLabelColor
    let clear = button(String(localized: "mac.sidebar.clearSearch", bundle: .lodyMac), #selector(clearSearch), "palette-clear")
    clear.contentTintColor = .lodyAccent
    let emptyMark = NSImageView(image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage())
    emptyMark.contentTintColor = .tertiaryLabelColor
    emptyMark.symbolConfiguration = .init(pointSize: 24, weight: .regular)
    emptyMark.setAccessibilityElement(false)
    for child in [emptyMark, emptyTitle, hint, clear] { empty.addArrangedSubview(child) }
    for child in [header, scroll, footer, empty] { child.translatesAutoresizingMaskIntoConstraints = false; body.addSubview(child) }
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: body.topAnchor), header.leadingAnchor.constraint(equalTo: body.leadingAnchor),
      header.trailingAnchor.constraint(equalTo: body.trailingAnchor), header.heightAnchor.constraint(equalToConstant: 52),
      back.widthAnchor.constraint(equalToConstant: 24),
      searchMark.widthAnchor.constraint(equalToConstant: 18),
      search.heightAnchor.constraint(equalToConstant: 24),
      clearQuery.widthAnchor.constraint(equalToConstant: 16), clearQuery.heightAnchor.constraint(equalToConstant: 24),
      footer.leadingAnchor.constraint(equalTo: body.leadingAnchor), footer.trailingAnchor.constraint(equalTo: body.trailingAnchor),
      footer.bottomAnchor.constraint(equalTo: body.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 44),
      scroll.leadingAnchor.constraint(equalTo: body.leadingAnchor, constant: 8), scroll.trailingAnchor.constraint(equalTo: body.trailingAnchor, constant: -8),
      scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
      empty.centerXAnchor.constraint(equalTo: body.centerXAnchor), empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
      empty.widthAnchor.constraint(lessThanOrEqualTo: body.widthAnchor, constant: -48),
    ])
    view = root
    reload()
  }

  func update(_ state: SessionListState) { self.state = state; reload() }
  func focusSearch() { view.window?.makeFirstResponder(search); search.selectText(nil) }

  func reload() {
    guard isViewLoaded else { return }
    let selectedId = selected?.id
    clearQuery.isHidden = search.stringValue.isEmpty
    rebuildFilter()
    let items = MacPaletteModel(state: state, mode: mode).items(query: search.stringValue, scope: scope, machineId: machineId)
    rows.removeAll()
    for item in items {
      if rows.last?.heading != item.section { rows.append((item.section, nil)) }
      rows.append((item.section, item))
    }
    updating = true
    table.reloadData()
    let index = rows.firstIndex { $0.item?.id == selectedId && selectedId != nil } ?? rows.firstIndex { $0.item != nil }
    if let index { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
    else { table.deselectAll(nil) }
    updating = false
    empty.isHidden = !items.isEmpty
    scroll.isHidden = items.isEmpty
    emptyTitle.stringValue = String(localized: "mac.palette.noResults \(search.stringValue)", bundle: .lodyMac)
    let listHeight = rows.reduce(CGFloat(0)) { $0 + ($1.item == nil ? 20 : 36) }
    var height = max(272, min(408, listHeight + 110))
    if items.isEmpty { height = 280 }
    preferredContentSize = NSSize(width: 640, height: height)
    onResize?(preferredContentSize)
    updatePrimary()
  }

  private var selected: MacPaletteModel.Item? {
    guard rows.indices.contains(table.selectedRow) else { return nil }
    return rows[table.selectedRow].item
  }

  private func updatePrimary() {
    primary.isEnabled = selected != nil
    let title = selected.map(primaryTitle) ?? String(localized: "mac.palette.open", bundle: .lodyMac)
    primary.title = title
    primary.setAccessibilityLabel(title)
  }

  private func primaryTitle(_ item: MacPaletteModel.Item) -> String {
    switch item.destination {
    case .chat: String(localized: "mac.palette.openChat", bundle: .lodyMac)
    case .project: mode == .projects ? String(localized: "mac.palette.useProject", bundle: .lodyMac) : String(localized: "mac.sidebar.newChat", bundle: .lodyMac)
    case .newChat, .manageProjects: item.title
    }
  }

  private func rebuildFilter() {
    filter.removeAllItems()
    if mode == .search {
      filter.addItems(withTitles: [String(localized: "mac.palette.all", bundle: .lodyMac), String(localized: "mac.palette.chats", bundle: .lodyMac), String(localized: "mac.settings.page.projects", bundle: .lodyMac)])
      filter.selectItem(at: scope.rawValue)
      return
    }
    filter.addItem(withTitle: String(localized: "mac.palette.allComputers", bundle: .lodyMac))
    filter.lastItem?.representedObject = ""
    for id in state.catalog.machineIds {
      filter.addItem(withTitle: state.catalog.machineNames[id] ?? id)
      filter.lastItem?.representedObject = id
    }
    if let item = filter.itemArray.first(where: { ($0.representedObject as? String) == machineId }) { filter.select(item) }
    else { machineId = ""; filter.selectItem(at: 0) }
  }

  @objc private func filterChanged() {
    if mode == .search { scope = MacPaletteModel.Scope(rawValue: filter.indexOfSelectedItem) ?? .all }
    else { machineId = filter.selectedItem?.representedObject as? String ?? "" }
    table.deselectAll(nil)
    reload()
    focusSearch()
  }
  @objc private func clearSearch() { search.stringValue = ""; reload(); focusSearch() }
  @objc private func cancel() { onClose?() }
  @objc private func confirm() { if let selected { onPick?(selected.destination) } }

  private func move(_ step: Int) {
    let selectable = rows.indices.filter { rows[$0].item != nil }
    guard !selectable.isEmpty else { return }
    let old = selectable.firstIndex(of: table.selectedRow) ?? 0
    let next = selectable[max(0, min(selectable.count - 1, old + step))]
    table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
    table.scrollRowToVisible(next)
  }

  func controlTextDidChange(_ obj: Notification) { table.deselectAll(nil); reload() }
  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.moveDown(_:)): move(1)
    case #selector(NSResponder.moveUp(_:)): move(-1)
    case #selector(NSResponder.insertNewline(_:)): confirm()
    case #selector(NSResponder.cancelOperation(_:)): cancel()
    default: return false
    }
    return true
  }

  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rows[row].item == nil ? 20 : 36 }
  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { rows[row].item != nil }
  func tableViewSelectionDidChange(_ notification: Notification) { if !updating { updatePrimary() } }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    guard rows[row].item != nil else { return NSTableRowView() }
    let view = MacPaletteRow()
    view.onHover = { [weak self] in
      guard let self, !updating, rows.indices.contains(row), rows[row].item != nil else { return }
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }
    return view
  }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    if let item = rows[row].item { return MacPaletteRow.cell(item) }
    let cell = NSTableCellView()
    let label = NSTextField(labelWithString: rows[row].heading)
    label.font = .preferredFont(forTextStyle: .caption1)
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(label)
    NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
    return cell
  }

  private func configure(_ button: NSButton, _ selector: Selector, _ id: String) {
    button.bezelStyle = .accessoryBarAction
    button.isBordered = false
    button.font = .preferredFont(forTextStyle: .body)
    button.target = self
    button.action = selector
    button.setAccessibilityIdentifier(id)
  }
  private func button(_ title: String, _ selector: Selector, _ id: String) -> NSButton {
    let button = NSButton(title: title, target: self, action: selector)
    configure(button, selector, id)
    return button
  }
  private func capsule(_ buttons: [NSButton]) -> NSView {
    let surface = NSGlassEffectView()
    surface.style = .regular
    surface.cornerRadius = 16
    if #available(macOS 27, *) { surface.effectIsInteractive = true }
    let stack = NSStackView(views: buttons)
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    let content = NSView()
    content.addSubview(stack)
    surface.contentView = content
    NSLayoutConstraint.activate([
      surface.heightAnchor.constraint(equalToConstant: 32),
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
      stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
    ])
    return surface
  }
}

@MainActor
private final class MacPaletteTable: NSTableView {
  var onMove: ((Int) -> Void)?
  var onConfirm: (() -> Void)?
  var onCancel: (() -> Void)?
  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 125: onMove?(1)
    case 126: onMove?(-1)
    case 36, 76: onConfirm?()
    case 53: onCancel?()
    default: super.keyDown(with: event)
    }
  }
}
