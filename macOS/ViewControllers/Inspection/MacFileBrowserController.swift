import AppKit

@MainActor
final class MacFileBrowserController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
  private final class Node: NSObject {
    let path: String
    let name: String
    let directory: Bool
    let target: MacInspectionTarget?
    init(path: String, name: String, directory: Bool, target: MacInspectionTarget? = nil) {
      self.path = path; self.name = name; self.directory = directory; self.target = target
    }
  }
  private let model: MacInspectionModel
  private let search = NSSearchField()
  private let outline = NSOutlineView()
  private let feedback = NSTextField(wrappingLabelWithString: "")
  private let retry = MacInspectionUI.button(MacInspectionUI.text("mac.inspection.retry"), "inspection-directory-retry") {}
  private var nodes: [String: Node] = [:]
  private var filtered: [Node] = []
  var onPick: ((MacInspectionTarget) -> Void)?

  init(model: MacInspectionModel) {
    self.model = model; super.init(nibName: nil, bundle: nil)
    preferredContentSize = NSSize(width: 350, height: 500)
  }
  required init?(coder: NSCoder) { nil }

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 500))
    search.placeholderString = MacInspectionUI.text("mac.inspection.filterFiles")
    search.delegate = self; search.setAccessibilityIdentifier("inspection-file-filter")
    let column = NSTableColumn(identifier: .init("file")); column.title = MacInspectionUI.text("mac.inspection.filesTitle")
    outline.addTableColumn(column); outline.outlineTableColumn = column; outline.headerView = nil
    outline.rowHeight = 30; outline.indentationPerLevel = 12
    outline.delegate = self; outline.dataSource = self
    outline.setAccessibilityIdentifier("inspection-file-tree")
    outline.target = self; outline.action = #selector(pick)
    let scroll = NSScrollView(); scroll.documentView = outline; scroll.hasVerticalScroller = true
    feedback.font = .systemFont(ofSize: 11); feedback.textColor = .secondaryLabelColor
    let clear = MacInspectionUI.button(MacInspectionUI.text("mac.inspection.clear"), "inspection-file-clear") { [weak self] in self?.search.stringValue = ""; self?.reload() }
    retry.target = self; retry.action = #selector(retryDirectory)
    let footer = NSStackView(views: [feedback, retry, clear]); footer.spacing = 6
    for child in [search, scroll, footer] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
    NSLayoutConstraint.activate([
      search.topAnchor.constraint(equalTo: view.topAnchor, constant: 12), search.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), search.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
      scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -6), footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12), footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
    ])
    model.directoryChanged = { [weak self] in self?.reload() }
    model.loadDirectory(""); reload()
  }
  override func viewDidAppear() { super.viewDidAppear(); view.window?.makeFirstResponder(search) }

  private func children(_ path: String) -> [Node] {
    (model.directories[path]?.value?.entries ?? []).filter { !$0.name.isEmpty && $0.name != "." && $0.name != ".." && !$0.name.contains("/") && !$0.name.contains("\\") }.sorted {
      if $0.directory != $1.directory { return $0.directory }
      return $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }.map { entry in
      let full = path.isEmpty ? entry.name : path + "/" + entry.name
      if let node = nodes[full] { return node }
      let target: MacInspectionTarget? = entry.directory ? nil : .file(full)
      let node = Node(path: full, name: entry.name, directory: entry.directory, target: target)
      nodes[full] = node; return node
    }
  }
  private func roots() -> [Node] {
    if !search.stringValue.isEmpty { return filtered }
    var result = children("")
    for target in model.attachments {
      let key = "attachment:" + String(describing: target)
      if nodes[key] == nil { nodes[key] = Node(path: key, name: MacInspectionUI.text("mac.inspection.attachments") + " · " + target.name, directory: false, target: target) }
      if let node = nodes[key] { result.append(node) }
    }
    return result
  }
  private func reload() {
    guard isViewLoaded else { return }
    // Materialize only responses already returned; this never recurses over the network.
    for path in model.directories.keys { _ = children(path) }
    let query = search.stringValue
    filtered = nodes.values.filter { !$0.directory && $0.path.localizedCaseInsensitiveContains(query) }.sorted { $0.path < $1.path }
    outline.reloadData()
    if query.isEmpty {
      for path in model.expandedFolders { if let node = nodes[path] { outline.expandItem(node) } }
    }
    let failed = model.directories.values.compactMap(\.error).first
    if let failed { feedback.stringValue = failed }
    else if model.directories.values.contains(where: { $0.value?.truncated == true }) { feedback.stringValue = MacInspectionUI.text("mac.inspection.truncated") }
    else if model.directories.values.contains(where: \.busy) { feedback.stringValue = MacInspectionUI.text("mac.inspection.loading") }
    else if !query.isEmpty, filtered.isEmpty { feedback.stringValue = MacInspectionUI.text("mac.inspection.noMatching") }
    else { feedback.stringValue = "" }
    retry.isHidden = failed == nil && !model.directories.values.contains(where: { $0.value?.truncated == true })
  }
  func controlTextDidChange(_ obj: Notification) { reload() }
  func outlineViewSelectionDidChange(_ notification: Notification) {
    guard let node = outline.item(atRow: outline.selectedRow) as? Node, let target = node.target else { return }
    onPick?(target)
  }
  func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { (item as? Node).map { children($0.path).count } ?? roots().count }
  func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { ((item as? Node).map { children($0.path) } ?? roots())[index] }
  func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? Node)?.directory == true && search.stringValue.isEmpty }
  func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
    guard let node = item as? Node else { return false }
    model.expandedFolders.insert(node.path); model.loadDirectory(node.path)
    return true
  }
  func outlineViewItemDidCollapse(_ notification: Notification) { if let node = notification.userInfo?["NSObject"] as? Node { model.expandedFolders.remove(node.path) } }
  func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
    guard let node = item as? Node else { return nil }
    let cell = NSTableCellView()
    let text = NSTextField(labelWithString: node.name); text.lineBreakMode = .byTruncatingMiddle
    let image = NSImageView(image: NSImage(systemSymbolName: node.directory ? "folder" : "doc.text", accessibilityDescription: nil) ?? NSImage())
    image.contentTintColor = .secondaryLabelColor
    let row = NSStackView(views: [image, text]); row.spacing = 6; row.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(row); cell.textField = text; cell.imageView = image
    cell.setAccessibilityIdentifier("inspection-tree-" + node.path); cell.toolTip = node.path
    NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: cell.leadingAnchor), row.trailingAnchor.constraint(equalTo: cell.trailingAnchor), row.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
    return cell
  }
  @objc private func pick() {
    guard let node = outline.item(atRow: outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow) as? Node else { return }
    if let target = node.target { onPick?(target) }
    else if outline.isItemExpanded(node) { outline.collapseItem(node) }
    else { outline.expandItem(node) }
  }
  @objc private func retryDirectory() {
    for (path, load) in model.directories where load.error != nil || load.value?.truncated == true { model.loadDirectory(path, force: true) }
  }
}
