import AppKit
import LodyData

@MainActor
final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
  enum Kind { case machine, project, session, gap }

  final class Node {
    let kind: Kind
    let id: String
    let title: String
    let row: MacSidebarModel.Row?
    var children: [Node]
    init(id: String, title: String, row: MacSidebarModel.Row? = nil, children: [Node] = [], kind: Kind = .session) {
      self.kind = kind
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
  private var collapsed: Set<String> = []
  private var reloading = false
  private let search = SidebarSearchField()
  private lazy var searchSurface = SidebarSearchSurface(field: search)
  private let filter = NSPopUpButton(frame: .zero, pullsDown: true)
  private let scroll = NSScrollView()
  private let empty = NSTextField(labelWithString: "")
  private var projectId: String?
  private var archived = false
  private let account: @MainActor () -> AuthAccount?
  private let workspacePicker = MacAccountButton(frame: .zero, pullsDown: true)
  private let archive = NSButton()

  private(set) lazy var topAccessory = makeTopAccessory()
  private(set) lazy var bottomAccessory = makeBottomAccessory()
  private var roots: [Node] = []
  private var observers: [NSObjectProtocol] = []
  private var selectedId: String?

  init(source: MacSessionsSource, account: @escaping @MainActor () -> AuthAccount? = { nil }) {
    self.source = source
    self.account = account
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  override func loadView() {
    search.placeholderString = String(localized: "mac.sidebar.search", bundle: .lodyMac)
    search.placeholderAttributedString = NSAttributedString(string: search.placeholderString ?? "", attributes: [
      .font: SidebarRowLayout.font, .foregroundColor: NSColor.labelColor,
    ])
    search.setAccessibilityIdentifier("sidebar-search")
    search.delegate = self
    search.controlSize = .regular
    search.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let column = NSTableColumn(identifier: .init("session"))
    outline.addTableColumn(column)
    outline.outlineTableColumn = column
    outline.headerView = nil
    outline.style = .sourceList
    outline.floatsGroupRows = false
    outline.intercellSpacing = .zero
    outline.backgroundColor = .clear
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
    scroll.autohidesScrollers = true
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
    let new = SidebarActionButton(title: String(localized: "mac.sidebar.newChat", bundle: .lodyMac), symbol: "square.and.pencil")
    new.contentTintColor = .labelColor
    new.target = self
    new.action = #selector(newSessionPressed)
    new.setAccessibilityIdentifier("sidebar-new-session")
    // One persistent native search field; Find only changes focus, never layout.
    let stack = NSStackView(views: [new, searchSurface])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 0
    stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 12, right: 8)
    new.translatesAutoresizingMaskIntoConstraints = false
    new.heightAnchor.constraint(equalToConstant: 32).isActive = true
    new.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
    searchSurface.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
    let accessory = NSSplitViewItemAccessoryViewController()
    accessory.automaticallyAppliesContentInsets = false
    accessory.view = stack
    if #available(macOS 26.1, *) { accessory.preferredScrollEdgeEffectStyle = .soft }
    return accessory
  }

  private func makeBottomAccessory() -> NSSplitViewItemAccessoryViewController {
    workspacePicker.alignment = .left
    workspacePicker.isBordered = false
    workspacePicker.bezelStyle = .accessoryBarAction
    workspacePicker.contentTintColor = .labelColor
    workspacePicker.font = .preferredFont(forTextStyle: .body)
    workspacePicker.symbolConfiguration = .init(pointSize: 18, weight: .regular)
    (workspacePicker.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
    workspacePicker.setAccessibilityIdentifier("sidebar-workspace")
    workspacePicker.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let help = MacSidebarChrome.button("questionmark.circle", title: String(localized: "mac.settings.page.about", bundle: .lodyMac),
                                     id: "sidebar-about", target: self, action: #selector(showAbout), size: 32)
    archive.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)
    archive.isBordered = true
    archive.bezelStyle = .accessoryBarAction
    archive.showsBorderOnlyWhileMouseInside = true
    archive.target = self
    archive.action = #selector(toggleArchive)
    archive.toolTip = String(localized: "mac.sidebar.archive", bundle: .lodyMac)
    archive.setAccessibilityLabel(archive.toolTip)
    archive.setAccessibilityIdentifier("sidebar-archive")
    archive.translatesAutoresizingMaskIntoConstraints = false
    archive.widthAnchor.constraint(equalToConstant: 32).isActive = true
    archive.heightAnchor.constraint(equalToConstant: 32).isActive = true
    workspacePicker.heightAnchor.constraint(equalToConstant: 32).isActive = true
    let settings = MacSidebarChrome.button("gearshape", title: String(localized: "mac.menu.settings", bundle: .lodyMac),
                                         id: "sidebar-settings", target: self, action: #selector(showSettings), size: 32)
    let accountGroup = MacSidebarChrome.group([workspacePicker])
    let toolsGroup = MacSidebarChrome.group([help, archive, settings])
    let accessory = MacSidebarChrome.accessory([accountGroup, NSView(), toolsGroup])
    accessory.automaticallyAppliesContentInsets = false
    if let stack = accessory.view as? NSStackView {
      stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)
      stack.spacing = 8
    }
    return accessory
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
    if changed {
      for machine in roots {
        for project in machine.children where project.children.contains(where: { $0.id == sessionId }) {
          collapsed.remove(project.id)
          outline.expandItem(machine)
          outline.expandItem(project)
        }
      }
    }
    let row = outline.row(forItem: node)
    if row >= 0 { outline.selectRowIndexes([row], byExtendingSelection: false) }
  }

  private func reload() {
    searchSurface.updateValue()
    let state = source.read()
    if let projectId, !state.catalog.projects.contains(where: { $0.id == projectId }) { self.projectId = nil }
    let model = MacSidebarModel(state: state, query: search.stringValue, projectId: projectId, archived: archived)
    var next: [Node] = []
    for group in model.groups {
      let project = Node(id: group.id, title: group.title, children: group.rows.map(Self.node), kind: .project)
      let machineId = "machine:" + group.machineId
      if let machine = next.first(where: { $0.id == machineId }) {
        machine.children.append(Node(id: "gap:" + group.id, title: "", kind: .gap))
        machine.children.append(project)
      } else {
        if !next.isEmpty { next.append(Node(id: "machine-gap:" + group.machineId, title: "", kind: .gap)) }
        next.append(Node(id: machineId, title: group.machineTitle, children: [project], kind: .machine))
      }
    }
    if next.isEmpty {
      next = [Node(id: "machine:empty", title: String(localized: "mac.settings.page.projects", bundle: .lodyMac), kind: .machine)]
    }
    roots = next
    let searching = !search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    empty.isHidden = !model.groups.isEmpty
    empty.stringValue = String(localized: searching || projectId != nil ? "mac.sidebar.noMatches" : "mac.sidebar.empty", bundle: .lodyMac)
    reloading = true
    outline.reloadData()
    for machine in roots where machine.kind == .machine {
      outline.expandItem(machine)
      for project in machine.children where project.kind == .project && (!collapsed.contains(project.id) || searching) { outline.expandItem(project) }
    }
    reloading = false
    rebuildProjectMenu(state)
    rebuildWorkspaceMenu(state)
    archive.state = archived ? .on : .off
    archive.contentTintColor = archived ? .lodyAccent : .secondaryLabelColor
    archive.setAccessibilityValue(archived ? "1" : "0")
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
    (roots + roots.flatMap(\.children) + roots.flatMap(\.children).flatMap(\.children)).first { $0.id == id }
  }

  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    (item as? Node)?.children.count ?? roots.count
  }

  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    (item as? Node)?.children[index] ?? roots[index]
  }

  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    guard let node = item as? Node else { return false }
    return node.kind == .machine || node.kind == .project
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
    if node.kind == .gap { return NSView() }
    let cell = NSTableCellView()
    cell.setAccessibilityIdentifier("sidebar-" + node.id)
    cell.setAccessibilityLabel(node.title)
    let label = NSTextField(labelWithString: node.title)
    if node.kind == .project {
      SidebarRowLayout.installTitle(label, in: cell)
      let folder = NSImageView(image: NSImage(systemSymbolName: "folder", accessibilityDescription: nil) ?? NSImage())
      SidebarRowLayout.installIcon(folder, in: cell)
      let toggle = NSButton(image: NSImage(), target: self, action: #selector(toggleProject(_:)))
      toggle.isBordered = false
      toggle.identifier = NSUserInterfaceItemIdentifier(node.id)
      toggle.setAccessibilityIdentifier("sidebar-project-toggle-" + node.id)
      toggle.symbolConfiguration = .init(pointSize: 10, weight: .medium)
      toggle.contentTintColor = .secondaryLabelColor
      configureDisclosure(toggle, node: node)
      toggle.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(toggle)
      NSLayoutConstraint.activate([
        toggle.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
        toggle.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        toggle.widthAnchor.constraint(equalToConstant: 28), toggle.heightAnchor.constraint(equalToConstant: 28),
      ])
    } else {
      label.font = .systemFont(ofSize: 12, weight: .medium)
      label.textColor = .secondaryLabelColor
      label.lineBreakMode = .byTruncatingTail
      label.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(label)
      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
        label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -72),
        label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
    }
    if node.kind == .machine, roots.first(where: { $0.kind == .machine }) === node {
      filter.isBordered = false
      filter.imagePosition = .imageOnly
      filter.symbolConfiguration = .init(pointSize: 14, weight: .regular)
      (filter.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
      filter.setAccessibilityIdentifier("sidebar-filter")
      filter.setAccessibilityLabel(String(localized: "mac.sidebar.filterProjects", bundle: .lodyMac))
      filter.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(filter)
      let add = MacSidebarChrome.button("folder.badge.plus", title: String(localized: "mac.sidebar.manageProjects", bundle: .lodyMac), id: "sidebar-manage-projects", target: self, action: #selector(showProjects))
      cell.addSubview(add)
      NSLayoutConstraint.activate([
        filter.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
        filter.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        filter.widthAnchor.constraint(equalToConstant: 28), filter.heightAnchor.constraint(equalToConstant: 28),
        add.trailingAnchor.constraint(equalTo: filter.leadingAnchor, constant: -4),
        add.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
    }
    return cell
  }

  func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
    guard let node = item as? Node else { return 32 }
    if node.kind == .gap { return node.id.hasPrefix("machine-gap:") ? 24 : 12 }
    return node.kind == .machine ? 28 : 32
  }

  func outlineViewItemDidCollapse(_ notification: Notification) {
    guard let node = notification.userInfo?["NSObject"] as? Node else { return }
    refreshDisclosure(node)
    guard !reloading else { return }
    collapsed.insert(node.id)
    onVisibleSessionsChange?()
  }

  func outlineViewItemDidExpand(_ notification: Notification) {
    guard let node = notification.userInfo?["NSObject"] as? Node else { return }
    refreshDisclosure(node)
    guard !reloading else { return }
    collapsed.remove(node.id)
    onVisibleSessionsChange?()
  }

  private func configureDisclosure(_ button: NSButton, node: Node) {
    let expanded = outline.isItemExpanded(node)
    button.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
    let key = expanded ? "mac.sidebar.collapseProject" : "mac.sidebar.expandProject"
    button.setAccessibilityLabel(String(localized: String.LocalizationValue(key), bundle: .lodyMac) + " " + node.title)
  }

  private func refreshDisclosure(_ node: Node) {
    guard node.kind == .project else { return }
    let row = outline.row(forItem: node)
    guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) else { return }
    for button in cell.subviews.compactMap({ $0 as? NSButton }) { configureDisclosure(button, node: node) }
  }

  @objc private func toggleProject(_ sender: NSButton) {
    guard let id = sender.identifier?.rawValue, let node = find(id) else { return }
    if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
  }

  func outlineViewSelectionDidChange(_ notification: Notification) {
    guard let node = outline.item(atRow: outline.selectedRow) as? Node, let row = node.row, row.id != selectedId else { return }
    selectedId = row.id
    onSelect?(row.id)
  }

  func controlTextDidChange(_ obj: Notification) { reload() }
  func controlTextDidBeginEditing(_ obj: Notification) { searchSurface.focused = true }
  func controlTextDidEndEditing(_ obj: Notification) { searchSurface.focused = false }

  @objc private func newSessionPressed() { onNewSession?() }

  @objc private func chooseProject(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    projectId = id.isEmpty ? nil : id
    reload()
  }

  func focusSearch() { view.window?.makeFirstResponder(search) }
  @objc private func toggleArchive() {
    archived.toggle()
    search.stringValue = ""
    projectId = nil
    reload()
  }

  private func rebuildWorkspaceMenu(_ state: SessionListState) {
    let menu = NSMenu()
    menu.autoenablesItems = false
    let user = account()?.user
    var name = state.workspaces.first { $0.id == state.workspaceId }?.name ?? "Lody"
    if let user, !user.name.isEmpty { name = user.name }
    let head = NSMenuItem(title: name, action: nil, keyEquivalent: "")
    head.image = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: nil)
    menu.addItem(head)
    let accountItem = NSMenuItem(title: String(localized: "mac.settings.page.account", bundle: .lodyMac), action: #selector(showAccount), keyEquivalent: "")
    accountItem.target = self
    menu.addItem(accountItem)
    menu.addItem(.separator())
    for workspace in state.workspaces {
      let item = NSMenuItem(title: workspace.name, action: #selector(chooseWorkspace(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = workspace.id
      item.state = workspace.id == state.workspaceId ? .on : .off
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let machines = NSMenuItem(title: String(localized: "mac.settings.page.machines", bundle: .lodyMac), action: #selector(showMachines), keyEquivalent: "")
    machines.target = self
    menu.addItem(machines)
    workspacePicker.menu = menu
  }

  @objc private func chooseWorkspace(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String, id != source.read().workspaceId else { return }
    source.selectWorkspace(id)
  }
  @objc private func showAccount() { onShowSettings?(.account) }
  @objc private func showSettings() { onShowSettings?(.general) }
  @objc private func showMachines() { onShowSettings?(.machines) }
  @objc private func showProjects() { onShowSettings?(.projects) }
  @objc private func showAbout() { onShowSettings?(.about) }
  @objc private func openTab(_ sender: NSMenuItem) { sender.identifier.map { onOpenTab?($0.rawValue) } }
  @objc private func openWindow(_ sender: NSMenuItem) { sender.identifier.map { onOpenWindow?($0.rawValue) } }
}
