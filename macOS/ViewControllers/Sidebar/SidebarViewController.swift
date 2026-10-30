import AppKit
import LodyData

@MainActor
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate, NSMenuDelegate {
  final class Node {
    let id: String
    let title: String
    let row: MacSidebarModel.Row?
    var children: [Node]
    init(id: String, title: String, row: MacSidebarModel.Row? = nil, children: [Node] = []) {
      self.id = id
      self.title = title
      self.row = row
      self.children = children
    }
  }

  var onSelect: ((String) -> Void)?
  var onNewSession: (() -> Void)?
  var onAction: ((MacSessionAction, String) -> Void)?
  var onOpenTab: ((String) -> Void)?
  var onOpenWindow: ((String) -> Void)?
  var onShowSettings: ((MacSettingsPage) -> Void)?
  var onWorkspaceChange: ((SessionListState) -> Void)?
  var onVisibleSessionsChange: (() -> Void)?
  weak var actions: MacSessionActions?
  private let source: MacSessionsSource
  private let outline = SidebarOutlineView()
  var outlineView: NSOutlineView { outline }
  private var collapsed: Set<String> = ["settled"]
  private var reloading = false
  private let search = NSSearchField()
  private let filter = NSPopUpButton(frame: .zero, pullsDown: true)
  private let scroll = NSScrollView()
  private let empty = NSTextField(labelWithString: "")
  private var projectId: String?
  private var spacerHeight: CGFloat = 1
  private var machineButton: NSButton?
  private(set) lazy var topAccessory = makeTopAccessory()
  private(set) lazy var bottomAccessory = makeBottomAccessory()
  private var roots: [Node] = []
  private var observers: [NSObjectProtocol] = []
  private var selectedId: String?

  init(source: MacSessionsSource) {
    self.source = source
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  override func loadView() {
    search.placeholderString = String(localized: "mac.sidebar.search", bundle: .lodyMac)
    search.setAccessibilityIdentifier("sidebar-search")
    search.delegate = self
    search.controlSize = .regular
    search.sendsSearchStringImmediately = true
    search.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let column = NSTableColumn(identifier: .init("session"))
    outline.addTableColumn(column)
    outline.outlineTableColumn = column
    outline.headerView = nil
    outline.style = .sourceList
    outline.floatsGroupRows = false
    outline.rowSizeStyle = .default
    outline.indentationPerLevel = 0
    outline.dataSource = self
    outline.delegate = self
    outline.autosaveExpandedItems = false
    outline.setAccessibilityIdentifier("sidebar-sessions")
    outline.menu = NSMenu()
    outline.menu?.delegate = self
    outline.onReturn = { [weak self] in
      guard let self, let id = self.selectedId else { return }
      self.onAction?(.rename, id)
    }
    scroll.documentView = outline
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    empty.font = .systemFont(ofSize: 12)
    empty.textColor = .secondaryLabelColor
    empty.alignment = .center
    empty.setAccessibilityIdentifier("sidebar-empty")
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 680))
    for view in [scroll, empty] {
      view.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(view)
    }
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: root.topAnchor),
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      empty.centerXAnchor.constraint(equalTo: root.safeAreaLayoutGuide.centerXAnchor),
      empty.centerYAnchor.constraint(equalTo: root.safeAreaLayoutGuide.centerYAnchor),
      empty.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -32),
    ])
    view = root
  }

  private func makeTopAccessory() -> NSSplitViewItemAccessoryViewController {
    filter.isBordered = false
    filter.imagePosition = .imageOnly
    filter.controlSize = .small
    filter.setAccessibilityIdentifier("sidebar-filter")
    filter.setAccessibilityLabel(String(localized: "mac.sidebar.filterProjects", bundle: .lodyMac))
    filter.toolTip = String(localized: "mac.sidebar.filterProjects", bundle: .lodyMac)
    filter.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      filter.widthAnchor.constraint(equalToConstant: 32),
      filter.heightAnchor.constraint(equalToConstant: 28),
    ])
    let projects = MacSidebarChrome.button("folder", title: String(localized: "mac.settings.page.projects", bundle: .lodyMac),
                                         id: "sidebar-projects", target: self, action: #selector(showProjects))
    let controls = MacSidebarChrome.group([filter, projects])
    let new = MacSidebarChrome.button("square.and.pencil", title: String(localized: "mac.sidebar.newSession", bundle: .lodyMac),
                                    id: "sidebar-new-session", target: self, action: #selector(newSessionPressed), glass: true)
    new.contentTintColor = .lodyAccent
    new.bezelColor = .lodyAccent
    new.tintProminence = .secondary
    return MacSidebarChrome.accessory([search, controls, new])
  }

  private func makeBottomAccessory() -> NSSplitViewItemAccessoryViewController {
    let settings = MacSidebarChrome.button("gearshape", title: String(localized: "mac.menu.settings", bundle: .lodyMac),
                                         id: "sidebar-settings", target: self, action: #selector(showSettings))
    let machines = MacSidebarChrome.button("desktopcomputer", title: String(localized: "mac.settings.page.machines", bundle: .lodyMac),
                                         id: "sidebar-machines", target: self, action: #selector(showMachines))
    machineButton = machines
    let projects = MacSidebarChrome.button("folder", title: String(localized: "mac.settings.page.projects", bundle: .lodyMac),
                                         id: "sidebar-manage-projects", target: self, action: #selector(showProjects))
    let utilities = MacSidebarChrome.group([settings, machines, projects])
    let about = MacSidebarChrome.button("info", title: String(localized: "mac.settings.page.about", bundle: .lodyMac),
                                      id: "sidebar-about", target: self, action: #selector(showAbout), glass: true)
    return MacSidebarChrome.accessory([utilities, NSView(), about])
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    guard let index = (0..<outline.numberOfRows).first(where: { (outline.item(atRow: $0) as? Node)?.id == "spacer" }) else { return }
    let occupied = (0..<outline.numberOfRows).reduce(CGFloat(0)) { height, row in
      guard row != index else { return height }
      return height + outline.rect(ofRow: row).height + outline.intercellSpacing.height
    }
    let available = scroll.contentView.bounds.height - scroll.contentInsets.top - scroll.contentInsets.bottom
    let next = max(1, available - occupied - 8)
    guard abs(next - spacerHeight) > 1 else { return }
    spacerHeight = next
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0
      context.allowsImplicitAnimation = false
      outline.noteHeightOfRows(withIndexesChanged: IndexSet(integer: index))
      outline.needsLayout = true
      outline.layoutSubtreeIfNeeded()
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    _ = topAccessory
    _ = bottomAccessory
    for name in source.changes {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.reload() }
      })
    }
    reload()
  }

  func select(sessionId: String?) {
    let changed = selectedId != sessionId
    selectedId = sessionId
    guard let sessionId, let node = find(sessionId) else {
      outline.deselectAll(nil)
      return
    }
    if changed, let group = roots.first(where: { $0.children.contains { $0.id == sessionId } }) {
      collapsed.remove(group.id)
      outline.expandItem(group)
    }
    let row = outline.row(forItem: node)
    if row >= 0 { outline.selectRowIndexes([row], byExtendingSelection: false) }
  }

  private func reload() {
    let state = source.read()
    if let projectId, !state.catalog.projects.contains(where: { $0.id == projectId }) { self.projectId = nil }
    let model = MacSidebarModel(state: state, query: search.stringValue, projectId: projectId)
    var next = model.pinned.map(Self.node)
    let searching = !search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if searching {
      next += model.groups.flatMap(\.rows).map(Self.node)
    } else {
      next += (model.groups.first { $0.id == "active" }?.rows ?? []).map(Self.node)
      next.append(Node(id: "spacer", title: ""))
      next += model.groups.filter { $0.id != "active" }.map { Node(id: $0.id, title: $0.title, children: $0.rows.map(Self.node)) }
    }
    let count = model.pinned.count + model.groups.flatMap(\.rows).count
    roots = count == 0 ? [] : next
    empty.isHidden = count != 0
    empty.stringValue = String(localized: searching || projectId != nil ? "mac.sidebar.noMatches" : "mac.sidebar.empty", bundle: .lodyMac)
    reloading = true
    outline.reloadData()
    for node in roots where node.row == nil && node.id != "spacer" && !collapsed.contains(node.id) { outline.expandItem(node) }
    reloading = false
    rebuildProjectMenu(state)
    let online = state.presence.onlineMachineIds.count
    let presence = String(localized: "mac.sidebar.machines \(online)", bundle: .lodyMac)
    machineButton?.setAccessibilityLabel(presence)
    machineButton?.toolTip = presence
    onWorkspaceChange?(state)
    select(sessionId: selectedId)
    view.needsLayout = true
    onVisibleSessionsChange?()
  }

  private func rebuildProjectMenu(_ state: SessionListState) {
    let menu = NSMenu()
    menu.autoenablesItems = false
    let head = NSMenuItem(title: String(localized: "mac.sidebar.filterProjects", bundle: .lodyMac), action: nil, keyEquivalent: "")
    head.image = NSImage(systemSymbolName: "line.3.horizontal.decrease", accessibilityDescription: nil)
    menu.addItem(head)
    let all = NSMenuItem(title: String(localized: "mac.sidebar.allProjects", bundle: .lodyMac), action: #selector(chooseProject(_:)), keyEquivalent: "")
    all.representedObject = ""
    all.target = self
    all.state = projectId == nil ? .on : .off
    menu.addItem(all)
    menu.addItem(.separator())
    for project in state.catalog.projects.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
      let item = NSMenuItem(title: project.name, action: #selector(chooseProject(_:)), keyEquivalent: "")
      item.representedObject = project.id
      item.target = self
      item.state = project.id == projectId ? .on : .off
      item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let manage = NSMenuItem(title: String(localized: "mac.sidebar.manageProjects", bundle: .lodyMac), action: #selector(showProjects), keyEquivalent: "")
    manage.target = self
    menu.addItem(manage)
    filter.menu = menu
    filter.contentTintColor = projectId == nil ? .secondaryLabelColor : .lodyAccent
  }

  var visibleIds: [String] {
    (0..<outline.numberOfRows).compactMap { (outline.item(atRow: $0) as? Node)?.row?.id }
  }

  func neighbor(of id: String?, step: Int) -> String? {
    let ids = visibleIds
    guard let id, let index = ids.firstIndex(of: id) else { return step > 0 ? ids.first : ids.last }
    let next = index + step
    return ids.indices.contains(next) ? ids[next] : nil
  }

  func contextMenu(for id: String) -> NSMenu {
    let menu = NSMenu()
    fill(menu, for: id)
    return menu
  }

  private func fill(_ menu: NSMenu, for id: String) {
    menu.removeAllItems()
    menu.autoenablesItems = false
    for (title, action, enabled) in [
      (String(localized: "mac.sidebar.openTab", bundle: .lodyMac), #selector(openTab(_:)), onOpenTab != nil),
      (String(localized: "mac.sidebar.openWindow", bundle: .lodyMac), #selector(openWindow(_:)), onOpenWindow != nil),
    ] {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
      item.target = self
      item.identifier = NSUserInterfaceItemIdentifier(id)
      item.isEnabled = enabled
      item.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
      menu.addItem(item)
    }
    menu.addItem(.separator())
    for action in MacSessionAction.menuOrder {
      menu.addItem(contextItem(action, id))
    }
    menu.addItem(.separator())
    menu.addItem(contextItem(.delete, id))
  }

  private func contextItem(_ action: MacSessionAction, _ id: String) -> NSMenuItem {
    let item = action.menuItem(actions?.title(action, sessionId: id) ?? action.defaultTitle, action: #selector(contextAction(_:)), target: self)
    item.isEnabled = actions?.isEnabled(action, sessionId: id) ?? true
    item.identifier = NSUserInterfaceItemIdentifier(id)
    return item
  }

  @objc private func contextAction(_ sender: NSMenuItem) {
    guard let id = sender.identifier?.rawValue,
          let action = (sender.representedObject as? String).flatMap(MacSessionAction.init(rawValue:)) else { return }
    onAction?(action, id)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard let node = outline.item(atRow: outline.clickedRow) as? Node, node.row != nil else {
      menu.removeAllItems()
      return
    }
    fill(menu, for: node.id)
  }

  private static func node(_ row: MacSidebarModel.Row) -> Node { Node(id: row.id, title: row.title, row: row) }

  private func find(_ id: String) -> Node? {
    (roots + roots.flatMap(\.children)).first { $0.id == id }
  }

  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    (item as? Node)?.children.count ?? roots.count
  }

  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    (item as? Node)?.children[index] ?? roots[index]
  }

  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    guard let node = item as? Node else { return false }
    return node.row == nil && node.id != "spacer"
  }

  func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { false }

  func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
    (item as? Node)?.row != nil
  }

  func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { SidebarRowView() }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let node = item as? Node else { return nil }
    if let row = node.row {
      let cell = SidebarSessionCell(row: row)
      cell.menuForRow = { [weak self] in self?.contextMenu(for: row.id) ?? NSMenu() }
      return cell
    }
    if node.id == "spacer" { return NSView() }
    let cell = NSTableCellView()
    cell.setAccessibilityIdentifier("sidebar-shelf-" + node.id)
    cell.setAccessibilityLabel(node.title)
    let label = NSTextField(labelWithString: node.title)
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 18),
      label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -28),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    let count = NSTextField(labelWithString: String(node.children.count))
    count.font = .systemFont(ofSize: 10)
    count.textColor = .secondaryLabelColor
    count.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(count)
    NSLayoutConstraint.activate([
      count.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
      count.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
    guard let node = item as? Node else { return 28 }
    if node.id == "spacer" { return spacerHeight }
    return node.row == nil ? 28 : 76
  }

  func outlineViewItemDidCollapse(_ notification: Notification) {
    guard !reloading, let node = notification.userInfo?["NSObject"] as? Node else { return }
    collapsed.insert(node.id)
    onVisibleSessionsChange?()
  }

  func outlineViewItemDidExpand(_ notification: Notification) {
    guard !reloading, let node = notification.userInfo?["NSObject"] as? Node else { return }
    collapsed.remove(node.id)
    onVisibleSessionsChange?()
  }

  func outlineViewSelectionDidChange(_ notification: Notification) {
    guard let node = outline.item(atRow: outline.selectedRow) as? Node, let row = node.row, row.id != selectedId else { return }
    selectedId = row.id
    onSelect?(row.id)
  }

  func controlTextDidChange(_ obj: Notification) { reload() }

  @objc private func newSessionPressed() { onNewSession?() }

  @objc private func chooseProject(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    projectId = id.isEmpty ? nil : id
    reload()
  }

  func focusSearch() { view.window?.makeFirstResponder(search) }
  @objc private func showSettings() { onShowSettings?(.general) }
  @objc private func showMachines() { onShowSettings?(.machines) }
  @objc private func showProjects() { onShowSettings?(.projects) }
  @objc private func showAbout() { onShowSettings?(.about) }
  @objc private func openTab(_ sender: NSMenuItem) { sender.identifier.map { onOpenTab?($0.rawValue) } }
  @objc private func openWindow(_ sender: NSMenuItem) { sender.identifier.map { onOpenWindow?($0.rawValue) } }
}
