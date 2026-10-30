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
  weak var actions: MacSessionActions?
  private let source: MacSessionsSource
  private let outline = SidebarOutlineView()
  var outlineView: NSOutlineView { outline }
  private var collapsed: Set<String> = []
  private var approvalQueue: [String] = []
  private var reloading = false
  private let search = NSSearchField()
  private let workspacePicker = NSPopUpButton()
  private var workspaceIds: [String] = []
  private let approvals = NSButton()
  private let account = NSTextField(labelWithString: "")
  private let machines = NSTextField(labelWithString: "")
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
    let newSession = SidebarActionButton(title: String(localized: "mac.sidebar.newSession", bundle: .lodyMac), symbol: "square.and.pencil")
    newSession.target = self
    newSession.action = #selector(newSessionPressed)
    workspacePicker.isBordered = false
    workspacePicker.font = .systemFont(ofSize: 13, weight: .semibold)
    workspacePicker.target = self
    workspacePicker.action = #selector(workspaceChanged)
    workspacePicker.setAccessibilityIdentifier("sidebar-workspace")
    search.placeholderString = String(localized: "mac.sidebar.search", bundle: .lodyMac)
    search.delegate = self
    search.controlSize = .regular
    approvals.bezelStyle = .accessoryBarAction
    approvals.isBordered = false
    approvals.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil)
    approvals.imagePosition = .imageLeading
    approvals.alignment = .left
    approvals.contentTintColor = .secondaryLabelColor
    approvals.setAccessibilityIdentifier("sidebar-approvals")
    approvals.target = self
    approvals.action = #selector(approvalsPressed)
    let column = NSTableColumn(identifier: .init("session"))
    outline.addTableColumn(column)
    outline.outlineTableColumn = column
    outline.headerView = nil
    outline.style = .sourceList
    outline.floatsGroupRows = false
    outline.rowSizeStyle = .default
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
    let scroll = NSScrollView()
    scroll.documentView = outline
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    account.font = .systemFont(ofSize: 12, weight: .medium)
    account.lineBreakMode = .byTruncatingTail
    machines.font = .systemFont(ofSize: 11)
    machines.textColor = .secondaryLabelColor
    machines.setAccessibilityIdentifier("sidebar-machines")
    let footer = NSStackView(views: [account, machines])
    footer.orientation = .vertical
    footer.alignment = .leading
    footer.spacing = 2
    let top = NSStackView(views: [workspacePicker, newSession, search, approvals])
    top.orientation = .vertical
    top.alignment = .leading
    top.spacing = 6
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
    for view in [top, scroll, footer] {
      view.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(view)
    }
    NSLayoutConstraint.activate([
      top.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 8),
      top.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
      top.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
      search.widthAnchor.constraint(equalTo: top.widthAnchor),
      scroll.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 8),
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      footer.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
      footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
      footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
      footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
    ])
    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    for name in source.changes {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.reload() }
      })
    }
    reload()
  }

  func select(sessionId: String?) {
    selectedId = sessionId
    guard let sessionId, let node = find(sessionId) else {
      outline.deselectAll(nil)
      return
    }
    let row = outline.row(forItem: node)
    if row >= 0 { outline.selectRowIndexes([row], byExtendingSelection: false) }
  }

  private func reload() {
    let state = source.read()
    let model = MacSidebarModel(state: state, query: search.stringValue)
    var next: [Node] = []
    if !model.pinned.isEmpty {
      next.append(Node(id: "pinned", title: String(localized: "mac.sidebar.pinned", bundle: .lodyMac), children: model.pinned.map(Self.node)))
    }
    next += model.groups.map { Node(id: "project:" + $0.id, title: $0.title, children: $0.rows.map(Self.node)) }
    roots = next
    reloading = true
    outline.reloadData()
    for node in roots where !search.stringValue.isEmpty || !collapsed.contains(node.id) { outline.expandItem(node) }
    reloading = false
    approvals.title = String(localized: "mac.sidebar.approvals \(model.needsApproval)", bundle: .lodyMac)
    approvals.contentTintColor = model.needsApproval > 0 ? .systemOrange : .secondaryLabelColor
    approvals.isEnabled = model.needsApproval > 0
    approvalQueue = model.approvals
    let ids = state.workspaces.map(\.id)
    if ids != workspaceIds {
      workspaceIds = ids
      workspacePicker.removeAllItems()
      workspacePicker.addItems(withTitles: state.workspaces.map(\.name))
    }
    workspacePicker.isHidden = ids.count < 2
    if let index = ids.firstIndex(of: state.workspaceId) { workspacePicker.selectItem(at: index) }
    let user = AuthSession.shared.snapshot.account?.user
    account.stringValue = state.workspace?.name ?? user?.name ?? ""
    let online = state.presence.onlineMachineIds.count
    machines.stringValue = String(localized: "mac.sidebar.machines \(online)", bundle: .lodyMac)
    select(sessionId: selectedId)
  }

  var visibleIds: [String] { roots.flatMap(\.children).map(\.id) }

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
    roots.flatMap(\.children).first { $0.id == id }
  }

  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
    (item as? Node)?.children.count ?? roots.count
  }

  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
    (item as? Node)?.children[index] ?? roots[index]
  }

  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
    (item as? Node)?.row == nil
  }

  func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool { false }

  func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
    (item as? Node)?.row != nil
  }

  func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { SidebarRowView() }

  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let node = item as? Node else { return nil }
    if let row = node.row { return SidebarSessionCell(row: row) }
    let cell = NSTableCellView()
    let label = NSTextField(labelWithString: node.title)
    label.font = .systemFont(ofSize: 11, weight: .semibold)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
      label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
    (item as? Node)?.row == nil ? 26 : outlineView.rowHeight
  }

  func outlineViewItemDidCollapse(_ notification: Notification) {
    guard !reloading, let node = notification.userInfo?["NSObject"] as? Node else { return }
    collapsed.insert(node.id)
  }

  func outlineViewItemDidExpand(_ notification: Notification) {
    guard !reloading, let node = notification.userInfo?["NSObject"] as? Node else { return }
    collapsed.remove(node.id)
  }

  func outlineViewSelectionDidChange(_ notification: Notification) {
    guard let node = outline.item(atRow: outline.selectedRow) as? Node, let row = node.row, row.id != selectedId else { return }
    selectedId = row.id
    onSelect?(row.id)
  }

  func controlTextDidChange(_ obj: Notification) { reload() }

  @objc private func newSessionPressed() { onNewSession?() }

  @objc private func approvalsPressed() {
    guard !approvalQueue.isEmpty else { return }
    let index = selectedId.flatMap(approvalQueue.firstIndex(of:)).map { ($0 + 1) % approvalQueue.count } ?? 0
    let id = approvalQueue[index]
    select(sessionId: id)
    onSelect?(id)
  }

  @objc private func workspaceChanged() {
    let index = workspacePicker.indexOfSelectedItem
    guard workspaceIds.indices.contains(index), workspaceIds[index] != source.read().workspaceId else { return }
    source.selectWorkspace(workspaceIds[index])
  }
}

final class SidebarOutlineView: NSOutlineView {
  var onReturn: (() -> Void)?

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty, selectedRow >= 0 {
      onReturn?()
      return
    }
    super.keyDown(with: event)
  }
}

final class SidebarRowView: NSTableRowView {
  override var isEmphasized: Bool {
    get { false }
    set {}
  }
}

final class SidebarActionButton: NSButton {
  convenience init(title: String, symbol: String) {
    self.init(frame: .zero)
    self.title = title
    image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    imagePosition = .imageLeading
    isBordered = false
    alignment = .left
    font = .systemFont(ofSize: 13)
  }
}
