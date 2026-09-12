import ExpoModulesCore
import UIKit

private struct SidebarItemID: Hashable {
  let section: String
  let row: String
}

/// Owns sidebar layout, outline expansion and persistent detail selection.
/// The grouped host is deliberately not in this view's rendering path.
final class LodySidebar: LodyAppearanceView, UICollectionViewDelegate {
  let onRowPress = EventDispatcher()
  let onRowAction = EventDispatcher()
  var previewUserId = ""
  var previewWorkspaceId = ""
  private var sections: [LodyListSection] = []
  private var rows: [SidebarItemID: LodyListRow] = [:]
  private var selectedRowId = ""
  private var accent: UIColor = .systemBlue
  private weak var scrollOwner: UIViewController?
  private let collection: UICollectionView
  private let placeholder = UILabel()
  private var dataSource: UICollectionViewDiffableDataSource<String, SidebarItemID>!

  private lazy var registration = UICollectionView.CellRegistration<UICollectionViewListCell, LodyListRow> { [weak self] cell, _, row in
    self?.configure(cell, row: row)
  }
  private lazy var headerRegistration = UICollectionView.SupplementaryRegistration<UICollectionViewListCell>(
    elementKind: UICollectionView.elementKindSectionHeader
  ) { [weak self] cell, _, index in
    guard let self, let id = self.dataSource.sectionIdentifier(for: index.section),
          let section = self.sections.first(where: { $0.id == id }) else { return }
    var content = UIListContentConfiguration.header()
    content.text = section.header
    cell.contentConfiguration = content
    cell.backgroundConfiguration = .clear()
    cell.accessibilityTraits = .header
  }

  required init(appContext: AppContext? = nil) {
    collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: .init(appearance: .sidebar)))
    super.init(appContext: appContext)
    _ = registration
    _ = headerRegistration
    backgroundColor = .secondarySystemBackground
    collection.backgroundColor = .secondarySystemBackground
    collection.contentInsetAdjustmentBehavior = .automatic
    collection.alwaysBounceVertical = true
    collection.keyboardDismissMode = .onDrag
    collection.topEdgeEffect.style = .soft
    collection.bottomEdgeEffect.style = .soft
    collection.delegate = self
    dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { [weak self] collection, index, id in
      guard let self, let row = self.rows[id] else { return nil }
      return collection.dequeueConfiguredReusableCell(using: self.registration, for: index, item: row)
    }
    dataSource.supplementaryViewProvider = { [weak self] collection, _, index in
      guard let self else { return nil }
      return collection.dequeueConfiguredReusableSupplementary(using: self.headerRegistration, for: index)
    }
    dataSource.sectionSnapshotHandlers.willExpandItem = { [weak self] item in
      self?.onRowPress(["id": item.row, "expanded": true])
    }
    dataSource.sectionSnapshotHandlers.willCollapseItem = { [weak self] item in
      self?.onRowPress(["id": item.row, "expanded": false])
    }
    let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
      guard let self, let id = self.dataSource.sectionIdentifier(for: index),
            let model = self.sections.first(where: { $0.id == id }) else { return nil }
      var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
      configuration.backgroundColor = .clear
      configuration.showsSeparators = false
      configuration.headerMode = model.rows.first?.parent == true || model.header.isEmpty ? .none : .supplementary
      configuration.leadingSwipeActionsConfigurationProvider = { [weak self] in self?.swipes(at: $0, leading: true) }
      configuration.trailingSwipeActionsConfigurationProvider = { [weak self] in self?.swipes(at: $0, leading: false) }
      let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
      section.contentInsets = .init(top: 4, leading: 12, bottom: 8, trailing: 12)
      return section
    }
    collection.setCollectionViewLayout(layout, animated: false)
    addSubview(collection)
    placeholder.font = .preferredFont(forTextStyle: .subheadline)
    placeholder.adjustsFontForContentSizeCategory = true
    placeholder.textColor = .secondaryLabel
    placeholder.textAlignment = .center
    placeholder.numberOfLines = 0
    addSubview(placeholder)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    collection.frame = bounds
    let inset = collection.adjustedContentInset
    placeholder.frame = bounds.inset(by: .init(top: inset.top + 24, left: 24, bottom: inset.bottom + 24, right: 24))
    attachScrollOwner()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      if scrollOwner?.contentScrollView(for: .top) === collection {
        scrollOwner?.setContentScrollView(nil, for: .top)
        scrollOwner?.setContentScrollView(nil, for: .bottom)
      }
      scrollOwner = nil
    } else {
      attachScrollOwner()
    }
  }

  private func attachScrollOwner() {
    guard window != nil, scrollOwner == nil else { return }
    var responder: UIResponder? = next
    while let current = responder {
      if let controller = current as? UIViewController {
        controller.setContentScrollView(collection, for: .top)
        controller.setContentScrollView(collection, for: .bottom)
        scrollOwner = controller
        return
      }
      responder = current.next
    }
  }

  func setSections(_ value: [LodyListSection]) {
    let previous = dataSource.snapshot()
    sections = value
    rows = Dictionary(value.flatMap { section in
      section.rows.map { (SidebarItemID(section: section.id, row: $0.id), $0) }
    }, uniquingKeysWith: { _, latest in latest })
    let sameSections = previous.sectionIdentifiers == value.map(\.id)
    if !sameSections {
      var snapshot = NSDiffableDataSourceSnapshot<String, SidebarItemID>()
      snapshot.appendSections(value.map(\.id))
      dataSource.apply(snapshot, animatingDifferences: false)
    }
    for section in value {
      var snapshot = NSDiffableDataSourceSectionSnapshot<SidebarItemID>()
      let items = section.rows.map { SidebarItemID(section: section.id, row: $0.id) }
      if let parent = items.first, section.rows[0].parent {
        snapshot.append([parent])
        snapshot.append(Array(items.dropFirst()), to: parent)
        if section.headerExpanded ?? true { snapshot.expand([parent]) }
      } else {
        snapshot.append(items)
      }
      dataSource.apply(snapshot, to: section.id, animatingDifferences: sameSections && window != nil && !UIAccessibility.isReduceMotionEnabled) { [weak self] in
        // A deep link can select before its catalog snapshot arrives. Read the
        // current detail, never a captured row from an earlier navigation.
        self?.synchronizeSelection()
      }
    }
    // Reconfigure visible content independently of snapshot animation.
    updateVisibleRows()
    placeholder.isHidden = !value.allSatisfy { $0.rows.isEmpty }
    collection.collectionViewLayout.invalidateLayout()
  }

  func setSelectedRowId(_ value: String) {
    guard value != selectedRowId else { return }
    selectedRowId = value
    synchronizeSelection()
    updateVisibleRows()
  }

  private func synchronizeSelection() {
    let index = rows.keys.first { $0.row == selectedRowId }.flatMap { dataSource.indexPath(for: $0) }
    let selection = index.map { [$0] } ?? []
    if (collection.indexPathsForSelectedItems ?? []) != selection {
      collection.selectItem(at: index, animated: false, scrollPosition: [])
    }
  }

  func setAccent(_ value: String) {
    accent = lodyTint(value) ?? .systemBlue
    updateVisibleRows()
  }

  func setPlaceholder(_ value: String) { placeholder.text = value }

  private func updateVisibleRows() {
    for index in collection.indexPathsForVisibleItems {
      guard let cell = collection.cellForItem(at: index) as? UICollectionViewListCell,
            let row = row(at: index) else { continue }
      configure(cell, row: row)
    }
  }

  private func configure(_ cell: UICollectionViewListCell, row: LodyListRow) {
    let project = row.parent || row.id.hasPrefix("project:")
    if project {
      let content = LodyProjectRowContent(row: row, accent: accent, density: .compact)
      cell.contentConfiguration = content
      cell.accessibilityLabel = content.accessibilityLabel
    } else {
      let tint = lodyTint(row.imageTint)
      let content = LodySessionRowContent(row: row, dot: tint,
        live: tint != nil && row.imageTint.hasPrefix("#") && row.badge.isEmpty, density: .compact)
      cell.contentConfiguration = content
      cell.accessibilityLabel = content.accessibilityLabel
    }
    cell.isAccessibilityElement = true
    cell.indentationWidth = 16
    cell.accessibilityIdentifier = row.id
    cell.accessibilityTraits = project ? [.button, .header] : .button
    if row.id == selectedRowId { cell.accessibilityTraits.insert(.selected) }
    if row.parent && !row.navigates {
      cell.accessories = [.outlineDisclosure(options: .init(style: .header, tintColor: .tertiaryLabel))]
    } else if project && row.navigates {
      cell.accessories = [.disclosureIndicator()]
    } else {
      cell.accessories = []
    }
    cell.automaticallyUpdatesBackgroundConfiguration = false
    cell.configurationUpdateHandler = { [weak self] cell, state in
      var visual = state
      visual.isSelected = row.id == self?.selectedRowId
      cell.backgroundConfiguration = LodySidebarCellBackground.configuration(for: visual)
      cell.accessibilityTraits = project ? [.button, .header] : .button
      if visual.isSelected { cell.accessibilityTraits.insert(.selected) }
    }
    cell.setNeedsUpdateConfiguration()
  }

  private func row(at index: IndexPath) -> LodyListRow? {
    dataSource.itemIdentifier(for: index).flatMap { rows[$0] }
  }

  func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
    row(at: indexPath)?.action == true
  }

  func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
    row(at: indexPath)?.action == true
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let row = row(at: indexPath) else { return }
    if row.parent && !row.navigates {
      collectionView.deselectItem(at: indexPath, animated: false)
      return
    }
    if row.preview == "session" { setSelectedRowId(row.id) }
    else { collectionView.deselectItem(at: indexPath, animated: true) }
    onRowPress(["id": row.id])
  }

  private func swipes(at index: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
    guard let row = row(at: index) else { return nil }
    return LodyListRowInteractions.swipes(row: row, leading: leading) { [weak self] id, actionId in
      self?.onRowAction(["id": id, "actionId": actionId])
    }
  }

  private func menu(at index: IndexPath) -> UIContextMenuConfiguration? {
    guard let row = row(at: index) else { return nil }
    return LodyListRowInteractions.menu(row: row, userId: previewUserId, workspaceId: previewWorkspaceId) { [weak self] id, actionId in
      self?.onRowAction(["id": id, "actionId": actionId])
    }
  }

  func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
    indexPaths.first.flatMap { menu(at: $0) }
  }

  func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
    menu(at: indexPath)
  }

  func collectionView(_ collectionView: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
    guard let id = configuration.identifier as? String else { return }
    animator.addCompletion { [weak self] in
      let target = id.hasPrefix("toggle:") ? "project:" + String(id.dropFirst(7)) : id
      self?.onRowPress(["id": target])
    }
  }
}
