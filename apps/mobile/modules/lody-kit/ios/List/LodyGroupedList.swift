import ExpoModulesCore
import UIKit

@Record
struct LodyListAction {
  var id: String = ""
  var title: String = ""
  var symbol: String = ""
  var tint: String = ""
  var destructive: Bool = false
}

@Record
struct LodyListRow {
  var id: String = ""
  var title: String = ""
  var subtitle: String = ""
  var value: String = ""
  var image: String = ""
  var filePath: String = ""
  var imageTint: String = ""
  var subtitleMono: Bool = false
  var unread: Bool = false
  var badge: String = ""
  var diff: [String: Int] = [:]
  var action: Bool = false
  var navigates: Bool = false
  var disclosure: Bool = false
  var destructive: Bool = false
  var parent: Bool = false
  var monogram: String = ""
  var pinned: Bool = false
  var actions: [LodyListAction] = []
  var leadingActions: [LodyListAction] = []
  var menuActions: [LodyListAction] = []
  var preview: String = ""
}

struct LodyListSection: Record {
  @Field var id: String = ""
  @Field var header: String = ""
  @Field var headerValue: String = ""
  @Field var headerActionId: String = ""
  @Field var headerExpanded: Bool? = nil
  @Field var footer: String = ""
  @Field var rows: [LodyListRow] = []
}

private final class ListAppearanceController: UIViewController {
  var onWillAppear: ((Bool, UIViewControllerTransitionCoordinator?) -> Void)?
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    onWillAppear?(animated, transitionCoordinator ?? parent?.transitionCoordinator)
  }
}

private final class SectionSupplementaryCell: UICollectionViewListCell {
  let arrow = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)))
  var expanded: Bool?
}

private final class SectionHeaderTap: UITapGestureRecognizer {}

private struct ListItemID: Hashable {
  let section: String
  let row: String
}

final class LodyGroupedList: ExpoView, UICollectionViewDelegate, UISearchBarDelegate {
  let onRowPress = EventDispatcher()
  let onRowAction = EventDispatcher()
  let onRefresh = EventDispatcher()
  let onSegmentChange = EventDispatcher()
  private let segments = UISegmentedControl(items: [])
  private let segmentContainer = UIView()
  /// Before iOS 26 the bar has no edge effect to extend, so the strip carries
  /// the bar's own material and reveals it the way `scrollEdgeAppearance` does.
  private let segmentMaterial = UIVisualEffectView(
    effect: UIBlurEffect(style: .systemChromeMaterial)
  )
  private let segmentHairline = UIView()
  private var scopeSearch: UISearchController?
  private var segmentLabels: [String] = []
  private var segmentsUseSearchScope = false
  private var selectedSegment = 0
  private let appearance = ListAppearanceController()
  private weak var scrollOwner: UIViewController?
  private var sections: [LodyListSection] = []
  private let collection: UICollectionView
  private let refreshControl = UIRefreshControl()
  private let placeholder = UILabel()
  private var placeholderText = ""

  private static var accent: UIColor = .systemBlue
  private var bottomInset: CGFloat = 0
  private var transparent = false
  private var contentStyle = false
  var previewUserId = ""
  var previewWorkspaceId = ""
  private var rowsByID: [ListItemID: LodyListRow] = [:]
  private var dataSource: UICollectionViewDiffableDataSource<String, ListItemID>!

  private static let restingCard = UIColor.tertiarySystemGroupedBackground

  private let registration = UICollectionView.CellRegistration<UICollectionViewListCell, LodyListRow> { cell, _, row in
    LodyGroupedList.configureSystem(cell, row)
  }

  private lazy var sessionRegistration = UICollectionView.CellRegistration<LodyIndentedCell, LodyListRow> { cell, _, row in
    LodyGroupedList.configureSession(cell, row)
  }

  private var outline: Bool { sections.contains { $0.rows.first?.parent == true } }

  private let projectRegistration = UICollectionView.CellRegistration<LodyIndentedCell, LodyListRow> { cell, _, row in
    LodyGroupedList.configureProject(cell, row)
  }

  private static func configureProject(_ cell: UICollectionViewListCell, _ row: LodyListRow) {
    cell.contentConfiguration = LodyProjectRowContent(row: row, accent: accent)
    cell.accessories = row.navigates
      ? [.disclosureIndicator()]
      : [.outlineDisclosure(options: .init(style: .header, tintColor: .tertiaryLabel))]
    cell.accessibilityIdentifier = row.id
    cell.accessibilityTraits = [.button, .header]
  }

  private static func configureSession(_ cell: LodyIndentedCell, _ row: LodyListRow) {
    let tint = lodyTint(row.imageTint)
    cell.contentConfiguration = LodySessionRowContent(
      row: row,
      dot: tint,
      live: tint != nil && row.imageTint.hasPrefix("#") && row.badge.isEmpty
    )
    cell.accessories = []
    cell.accessibilityIdentifier = row.id
    cell.accessibilityTraits = row.action ? .button : .staticText
  }

  private static func configureSystem(_ cell: UICollectionViewListCell, _ row: LodyListRow) {
    cell.accessibilityIdentifier = row.id
    let accent = LodyGroupedList.accent
    var content = UIListContentConfiguration.subtitleCell()
    content.text = row.title
    let subtitle = [row.subtitle, row.badge].filter { !$0.isEmpty }.joined(separator: " · ")
    content.secondaryText = subtitle.isEmpty ? nil : subtitle
    content.textProperties.numberOfLines = 0
    content.secondaryTextProperties.numberOfLines = 1
    if row.subtitleMono {
      content.secondaryTextProperties.font = .monospacedSystemFont(
        ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
        weight: .regular
      )
    }
    content.textProperties.color = row.destructive ? .systemRed : .label
    if !row.filePath.isEmpty {
      content.image = MaterialFileIcon.image(for: row.filePath)
    } else if let url = LodyListPhoto.url(row.image) {
      if let image = LodyListPhoto.image(for: url, ready: { [weak cell] image in
        guard let cell, cell.accessibilityIdentifier == row.id,
              var next = cell.contentConfiguration as? UIListContentConfiguration else { return }
        LodyListPhoto.apply(&next, image: image)
        cell.contentConfiguration = next
      }) {
        LodyListPhoto.apply(&content, image: image)
      } else if let placeholder = UIImage(systemName: "person.crop.circle.fill") {
        LodyListPhoto.apply(&content, image: placeholder, placeholder: true)
      }
    } else if !row.image.isEmpty {
      content.image = UIImage(systemName: row.image)
      content.imageProperties.tintColor =
        lodyTint(row.imageTint) ?? (row.destructive ? .systemRed : accent)
      content.imageProperties.preferredSymbolConfiguration = .init(textStyle: .title3)
    }
    cell.contentConfiguration = content
    var accessories: [UICellAccessory] = []
    if !row.value.isEmpty {
      var options = UICellAccessory.LabelOptions()
      options.tintColor = .secondaryLabel
      accessories.append(.label(text: row.value, options: options))
    }
    if row.disclosure { accessories.append(.disclosureIndicator()) }
    cell.accessories = accessories
    cell.accessibilityTraits = row.action ? .button : .staticText
  }

  private let headerRegistration = UICollectionView.SupplementaryRegistration<SectionSupplementaryCell>(
    elementKind: UICollectionView.elementKindSectionHeader
  ) { _, _, _ in }

  private let footerRegistration = UICollectionView.SupplementaryRegistration<SectionSupplementaryCell>(
    elementKind: UICollectionView.elementKindSectionFooter
  ) { _, _, _ in }

  required init(appContext: AppContext? = nil) {
    collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: .init(appearance: .insetGrouped)))
    super.init(appContext: appContext)
    // UIKit rejects a registration created inside the cell provider.
    _ = sessionRegistration
    collection.backgroundColor = .systemGroupedBackground
    collection.contentInsetAdjustmentBehavior = .automatic
    collection.alwaysBounceVertical = true
    collection.keyboardDismissMode = .onDrag
    dataSource = UICollectionViewDiffableDataSource<String, ListItemID>(collectionView: collection) { [weak self] collection, index, id in
      guard let self, let row = self.rowsByID[id] else { return nil }
      return self.cell(in: collection, at: index, row: row)
    }
    dataSource.supplementaryViewProvider = { [weak self] collection, kind, index in
      self?.supplementary(in: collection, kind: kind, at: index)
    }
    dataSource.sectionSnapshotHandlers.willExpandItem = { [weak self] item in
      self?.onRowPress(["id": item.row, "expanded": true])
    }
    dataSource.sectionSnapshotHandlers.willCollapseItem = { [weak self] item in
      self?.onRowPress(["id": item.row, "expanded": false])
    }
    collection.delegate = self
    let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
      var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
      // The collection owns the ground; the layout must not repaint it at full detent.
      configuration.backgroundColor = .clear
      // `.firstItemInSection` splits the inset card into a header card and an
      // items card; a parent row is a plain first item so the card stays whole.
      let outline = self?.section(at: index)?.rows.first?.parent ?? false
      configuration.headerMode = outline ? .none : .supplementary
      configuration.footerMode = outline ? .none : .supplementary
      configuration.leadingSwipeActionsConfigurationProvider = { indexPath in
        self?.swipeActions(at: indexPath, leading: true)
      }
      configuration.trailingSwipeActionsConfigurationProvider = { indexPath in
        self?.swipeActions(at: indexPath, leading: false)
      }
      let section = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
      if outline {
        // The decoration spans the section frame including its insets; matching
        // them puts the card exactly under the rows.
        let card = NSCollectionLayoutDecorationItem.background(elementKind: LodySectionCardView.kind)
        card.contentInsets = section.contentInsets
        section.decorationItems = [card]
      }
      return section
    }
    layout.register(LodySectionCardView.self, forDecorationViewOfKind: LodySectionCardView.kind)
    collection.setCollectionViewLayout(layout, animated: false)
    if #available(iOS 26.0, *) {
      collection.topEdgeEffect.style = .soft
      collection.bottomEdgeEffect.style = .soft
    }
    refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
    collection.refreshControl = refreshControl
    placeholder.textAlignment = .center
    placeholder.numberOfLines = 0
    placeholder.textColor = .secondaryLabel
    placeholder.font = .preferredFont(forTextStyle: .subheadline)
    placeholder.adjustsFontForContentSizeCategory = true
    placeholder.isHidden = true
    addSubview(collection)
    addSubview(placeholder)
    segments.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
    segmentContainer.isHidden = true
    if #unavailable(iOS 26.0) {
      segmentMaterial.alpha = 0
      segmentHairline.backgroundColor = .separator
      segmentHairline.alpha = 0
      segmentContainer.addSubview(segmentMaterial)
      segmentContainer.addSubview(segmentHairline)
    }
    segmentContainer.addSubview(segments)
    addSubview(segmentContainer)
    if #available(iOS 26.0, *) {
      // Registers the overlay with the scroll view so UIKit shapes the top edge
      // effect around it. Without this the control floats with nothing behind it.
      let interaction = UIScrollEdgeElementContainerInteraction()
      interaction.scrollView = collection
      interaction.edge = .top
      segmentContainer.addInteraction(interaction)
    }
    appearance.view = UIView(frame: .zero)
    appearance.view.isUserInteractionEnabled = false
    appearance.onWillAppear = { [weak self] animated, coordinator in
      self?.deselectOnReturn(animated: animated, coordinator: coordinator)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    collection.frame = bounds
    updateBottomInset()
    let insets = collection.adjustedContentInset
    if !segmentContainer.isHidden {
      // Content starts below the bar plus the strip; the strip sits in that gap.
      let top = max(0, insets.top - collection.contentInset.top)
      segmentContainer.frame = CGRect(x: 0, y: top, width: bounds.width, height: segmentBarHeight)
      segments.frame = segmentContainer.bounds.insetBy(dx: 20, dy: 8)
      if #unavailable(iOS 26.0) {
        segmentMaterial.frame = segmentContainer.bounds
        let hairline = 1 / UIScreen.main.scale
        segmentHairline.frame = CGRect(
          x: 0, y: segmentBarHeight - hairline, width: bounds.width, height: hairline
        )
        updateSegmentMaterial()
      }
    }
    placeholder.frame = bounds.inset(by: UIEdgeInsets(top: insets.top + 24, left: 32, bottom: insets.bottom + 24, right: 32))
    attachScrollOwner()
  }

  override func willMove(toSuperview newSuperview: UIView?) {
    if newSuperview == nil, appearance.parent != nil {
      appearance.willMove(toParent: nil)
      appearance.view.removeFromSuperview()
      appearance.removeFromParent()
    }
    super.willMove(toSuperview: newSuperview)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      detachSegments()
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
        attachSegments(to: controller)
        if appearance.parent == nil {
          controller.addChild(appearance)
          addSubview(appearance.view)
          appearance.didMove(toParent: controller)
        }
        return
      }
      responder = current.next
    }
  }

  /// The bar owns the segmented control, the way Calendar's New sheet does:
  /// content scrolls under it and the navigation bar supplies the material and
  /// the scroll edge effect. A floating sibling view gets neither.
  private var segmentBarHeight: CGFloat { 52 }

  private func updateSegmentMaterial() {
    guard #unavailable(iOS 26.0) else { return }
    let scrolled = collection.contentOffset.y + collection.adjustedContentInset.top > 0.5
    let alpha: CGFloat = scrolled ? 1 : 0
    guard segmentMaterial.alpha != alpha else { return }
    segmentMaterial.alpha = alpha
    segmentHairline.alpha = alpha
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    updateSegmentMaterial()
  }

  /// The edge effect covers the adjusted content inset region, and
  /// `contentInset` feeds into that — unlike `additionalSafeAreaInsets`, which
  /// this scroll view never sees because react-native-screens owns the safe area.
  private func syncSegmentInset() {
    let wanted = segmentContainer.isHidden ? 0 : segmentBarHeight
    guard collection.contentInset.top != wanted else { return }
    collection.contentInset.top = wanted
    collection.verticalScrollIndicatorInsets.top = wanted
    setNeedsLayout()
  }

  private func attachSegments(to controller: UIViewController) {
    guard segments.numberOfSegments > 0 else { return }
    // No public API puts an arbitrary view in the bar's stacked palette; the
    // only thing that rides there is a search bar. Its scope bar, however, is a
    // real segmented control, and `.manual` activation keeps it visible without
    // search being active — the Calendar "New" layout, with public API only.
    guard segmentsUseSearchScope else { return }
    let item = controller.navigationItem
    let search = scopeSearch ?? UISearchController(searchResultsController: nil)
    scopeSearch = search
    search.scopeBarActivation = .manual
    search.hidesNavigationBarDuringPresentation = false
    search.obscuresBackgroundDuringPresentation = false
    search.searchBar.delegate = self
    search.searchBar.scopeButtonTitles = segmentLabels
    search.searchBar.showsScopeBar = true
    search.searchBar.selectedScopeButtonIndex = selectedSegment
    item.preferredSearchBarPlacement = .stacked
    item.hidesSearchBarWhenScrolling = false
    item.searchController = search
  }

  private func detachSegments() {
    guard let item = scrollOwner?.navigationItem else { return }
    if scopeSearch != nil, item.searchController === scopeSearch {
      item.searchController = nil
    }
    scopeSearch = nil
  }

  func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange index: Int) {
    guard index != selectedSegment else { return }
    selectedSegment = index
    onSegmentChange(["index": index])
  }

  func setSegmentsUseSearchScope(_ value: Bool) {
    segmentsUseSearchScope = value
  }

  func setSegments(_ labels: [String]) {
    segmentLabels = labels
    segments.removeAllSegments()
    for (index, label) in labels.enumerated() { segments.insertSegment(withTitle: label, at: index, animated: false) }
    segments.selectedSegmentIndex = selectedSegment
    segmentContainer.isHidden = labels.isEmpty || segmentsUseSearchScope
    syncSegmentInset()
    if labels.isEmpty {
      detachSegments()
    } else if let controller = scrollOwner {
      attachSegments(to: controller)
    }
    collection.contentInset.top = labels.isEmpty ? 0 : 60
    setNeedsLayout()
  }

  func setSelectedSegment(_ index: Int) {
    selectedSegment = index
    segments.selectedSegmentIndex = index
    scopeSearch?.searchBar.selectedScopeButtonIndex = index
  }

  @objc private func segmentChanged() {
    selectedSegment = segments.selectedSegmentIndex
    onSegmentChange(["index": selectedSegment])
    collection.setContentOffset(CGPoint(x: 0, y: -collection.adjustedContentInset.top), animated: false)
  }

  func setSections(_ value: [LodyListSection]) {
    let previous = dataSource.snapshot()
    sections = value
    rowsByID = Dictionary(value.flatMap { section in
      section.rows.map { (ListItemID(section: section.id, row: $0.id), $0) }
    }, uniquingKeysWith: { _, latest in latest })
    if contentStyle, value.contains(where: { $0.rows.first?.parent == true }) {
      applyOutline(value, previous: previous)
      updatePlaceholder()
      return
    }
    var snapshot = NSDiffableDataSourceSnapshot<String, ListItemID>()
    for section in value {
      snapshot.appendSections([section.id])
      snapshot.appendItems(section.rows.map { ListItemID(section: section.id, row: $0.id) }, toSection: section.id)
    }
    let existing = Set(previous.itemIdentifiers)
    snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { existing.contains($0) })
    // Start disclosure rotation alongside the snapshot's row animation.
    for index in collection.indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionHeader) {
      guard previous.sectionIdentifiers.indices.contains(index.section),
            let section = value.first(where: { $0.id == previous.sectionIdentifiers[index.section] }),
            let view = collection.supplementaryView(forElementKind: UICollectionView.elementKindSectionHeader, at: index) as? SectionSupplementaryCell else { continue }
      configureSupplementary(view, section: section, header: true)
    }
    dataSource.apply(snapshot, animatingDifferences: window != nil && !previous.sectionIdentifiers.isEmpty && !UIAccessibility.isReduceMotionEnabled) { [weak self] in
      guard let self else { return }
      for kind in [UICollectionView.elementKindSectionHeader, UICollectionView.elementKindSectionFooter] {
        for index in self.collection.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
          if let view = self.collection.supplementaryView(forElementKind: kind, at: index) as? SectionSupplementaryCell,
             let section = self.section(at: index.section) {
            self.configureSupplementary(view, section: section, header: kind == UICollectionView.elementKindSectionHeader)
          }
        }
      }
      self.collection.collectionViewLayout.invalidateLayout()
    }
    updatePlaceholder()
  }

  /// Section snapshots own expansion, so a parent row collapses its children
  /// with UIKit's outline animation instead of a React round trip. A section
  /// order change rebuilds without animation: the flat snapshot that reorders
  /// sections carries no items, and re-adding them animated would replay every
  /// row.
  private func applyOutline(_ value: [LodyListSection], previous: NSDiffableDataSourceSnapshot<String, ListItemID>) {
    let ids = value.map(\.id)
    let sameSections = previous.sectionIdentifiers == ids
    if !sameSections {
      var main = NSDiffableDataSourceSnapshot<String, ListItemID>()
      main.appendSections(ids)
      dataSource.apply(main, animatingDifferences: false)
    }
    let animate = sameSections && window != nil && !UIAccessibility.isReduceMotionEnabled
    for section in value {
      var snapshot = NSDiffableDataSourceSectionSnapshot<ListItemID>()
      let items = section.rows.map { ListItemID(section: section.id, row: $0.id) }
      if let parent = items.first, section.rows[0].parent {
        snapshot.append([parent])
        snapshot.append(Array(items.dropFirst()), to: parent)
        if section.headerExpanded ?? true { snapshot.expand([parent]) }
      } else {
        snapshot.append(items)
      }
      dataSource.apply(snapshot, to: section.id, animatingDifferences: animate)
    }
    for index in collection.indexPathsForVisibleItems {
      guard let cell = collection.cellForItem(at: index) as? UICollectionViewListCell, let row = row(at: index) else { continue }
      configure(cell, row: row)
    }
  }

  func setContentStyle(_ value: Bool) {
    guard value != contentStyle else { return }
    contentStyle = value
    collection.reloadData()
  }

  /// A sheet paints its own material. Dropping the list's ground lets that
  /// material show between groups. A tertiary grouped surface keeps cells
  /// distinct when the expanded sheet switches to an opaque background.
  func setTransparent(_ value: Bool) {
    guard value != transparent else { return }
    transparent = value
    collection.backgroundColor = value ? .clear : .systemGroupedBackground
    collection.reloadData()
  }

  func setBottomInset(_ height: CGFloat) {
    bottomInset = height
    updateBottomInset()
  }

  private func updateBottomInset() {
    let wanted = max(0, bottomInset - collection.safeAreaInsets.bottom)
    guard collection.contentInset.bottom != wanted else { return }
    collection.contentInset.bottom = wanted
    collection.verticalScrollIndicatorInsets.bottom = wanted
  }

  func setPreviewUserId(_ value: String) {
    previewUserId = value
  }

  func setPreviewWorkspaceId(_ value: String) {
    previewWorkspaceId = value
  }

  func setAccent(_ value: String) {
    guard let color = lodyTint(value), color != LodyGroupedList.accent else { return }
    LodyGroupedList.accent = color
    collection.reloadData()
  }

  func setRefreshing(_ value: Bool) {
    if value, !refreshControl.isRefreshing {
      refreshControl.beginRefreshing()
    } else if !value, refreshControl.isRefreshing {
      refreshControl.endRefreshing()
    }
  }

  func setPlaceholder(_ value: String) {
    placeholderText = value
    updatePlaceholder()
  }

  private func updatePlaceholder() {
    let empty = sections.isEmpty || sections.allSatisfy { $0.rows.isEmpty && $0.headerActionId.isEmpty }
    placeholder.text = placeholderText
    placeholder.isHidden = !empty || placeholderText.isEmpty
  }

  @objc private func refreshPulled() {
    onRefresh([:])
  }

  private enum RowKind { case system, session, project }

  private func kind(of row: LodyListRow) -> RowKind {
    guard contentStyle else { return .system }
    if row.parent { return .project }
    return row.value.isEmpty && row.badge.isEmpty ? .system : .session
  }

  private func cell(in collectionView: UICollectionView, at indexPath: IndexPath, row: LodyListRow) -> UICollectionViewListCell {
    let cell: UICollectionViewListCell
    switch kind(of: row) {
    case .system: cell = collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: row)
    case .session: cell = collectionView.dequeueConfiguredReusableCell(using: sessionRegistration, for: indexPath, item: row)
    case .project: cell = collectionView.dequeueConfiguredReusableCell(using: projectRegistration, for: indexPath, item: row)
    }
    decorate(cell, row: row)
    return cell
  }

  private func configure(_ cell: UICollectionViewListCell, row: LodyListRow) {
    switch kind(of: row) {
    case .system: Self.configureSystem(cell, row)
    case .session: if let cell = cell as? LodyIndentedCell { Self.configureSession(cell, row) }
    case .project: Self.configureProject(cell, row)
    }
    decorate(cell, row: row)
  }

  private func decorate(_ cell: UICollectionViewListCell, row: LodyListRow) {
    // Outline children carry indentation level 1; the row views own their columns.
    cell.indentationWidth = 0
    cell.configurationUpdateHandler = nil
    cell.automaticallyUpdatesBackgroundConfiguration = true
    if contentStyle {
      cell.automaticallyUpdatesBackgroundConfiguration = false
      if var content = cell.contentConfiguration as? UIListContentConfiguration {
        content.textProperties.numberOfLines = 2
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        content.directionalLayoutMargins = .init(top: 12, leading: 22, bottom: 12, trailing: 22)
        if outline, row.navigates { content.textProperties.color = LodyGroupedList.accent }
        cell.contentConfiguration = content
      }
      if outline {
        cell.configurationUpdateHandler = { cell, state in
          cell.backgroundConfiguration = LodyListCellBackground.outlineConfiguration(for: state)
        }
      } else {
        cell.configurationUpdateHandler = { cell, state in
          let visual = LodyListCellBackground.visualState(for: state)
          cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell().updated(for: visual)
        }
      }
    } else if transparent {
      // A static backgroundConfiguration freezes the cell's appearance, so the
      // highlighted and selected states stop rendering. The update handler
      // keeps UIKit's state resolution and only forces the resting color to be
      // opaque, which the glass sheet context otherwise makes translucent.
      cell.configurationUpdateHandler = { cell, state in
        var background = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
        if !state.isHighlighted && !state.isSelected {
          background.backgroundColor = LodyGroupedList.restingCard
        }
        cell.backgroundConfiguration = background
      }
    } else {
      cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
    }
  }

  private func section(at index: Int) -> LodyListSection? {
    guard let id = dataSource.sectionIdentifier(for: index) else { return nil }
    return sections.first { $0.id == id }
  }

  private func supplementary(in collectionView: UICollectionView, kind: String, at indexPath: IndexPath) -> UICollectionReusableView? {
    guard let section = section(at: indexPath.section) else { return nil }
    let header = kind == UICollectionView.elementKindSectionHeader
    let view = collectionView.dequeueConfiguredReusableSupplementary(
      using: header ? headerRegistration : footerRegistration,
      for: indexPath
    )
    configureSupplementary(view, section: section, header: header)
    return view
  }

  private func configureSupplementary(_ view: SectionSupplementaryCell, section: LodyListSection, header: Bool) {
    let text = header ? section.header : section.footer
    if view.accessibilityIdentifier != section.headerActionId { view.expanded = nil }
    if !header || section.headerExpanded == nil { view.accessories = [] }
    view.accessibilityValue = nil
    view.accessibilityIdentifier = header ? section.headerActionId : nil
    view.accessibilityTraits = header ? .header : .staticText
    view.isUserInteractionEnabled = header && !section.headerActionId.isEmpty
    guard !text.isEmpty else {
      view.contentConfiguration = nil
      return
    }
    var content = header ? UIListContentConfiguration.groupedHeader() : UIListContentConfiguration.groupedFooter()
    content.text = text
    content.textProperties.numberOfLines = 0
    if contentStyle {
      content.directionalLayoutMargins = .init(top: 10, leading: 22, bottom: 10, trailing: 22)
      if header {
        let title = NSMutableAttributedString(string: text, attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline), .foregroundColor: UIColor.secondaryLabel])
        if !section.headerValue.isEmpty {
          title.append(NSAttributedString(string: "  " + section.headerValue, attributes: [.font: UIFont.preferredFont(forTextStyle: .caption1), .foregroundColor: UIColor.tertiaryLabel]))
        }
        content.text = nil
        content.attributedText = title
        content.directionalLayoutMargins.top = 14
        content.directionalLayoutMargins.bottom = 14
      }
    }
    if header && !section.headerActionId.isEmpty {
      view.accessibilityTraits = [.header, .button]
      if let expanded = section.headerExpanded {
        let arrow = view.arrow
        let changed = view.expanded != expanded
        let shouldAnimate = view.expanded != nil && changed && view.window != nil && !UIAccessibility.isReduceMotionEnabled
        view.expanded = expanded
        let rotation = { arrow.transform = expanded ? CGAffineTransform(rotationAngle: .pi / 2) : .identity }
        if shouldAnimate {
          UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: rotation)
        } else if changed {
          UIView.performWithoutAnimation(rotation)
        }
        arrow.tintColor = .secondaryLabel
        arrow.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        arrow.contentMode = .center
        if view.accessories.isEmpty {
          view.accessories = [.customView(configuration: .init(customView: arrow, placement: .trailing()))]
        }
        view.accessibilityValue = LodyStrings.text(expanded ? "native.list.expanded" : "native.list.collapsed")
      } else {
        view.accessories = [.disclosureIndicator()]
      }
      if !(view.gestureRecognizers?.contains { $0 is SectionHeaderTap } ?? false) {
        view.addGestureRecognizer(SectionHeaderTap(target: self, action: #selector(headerPressed(_:))))
      }
    }
    view.contentConfiguration = content
    view.backgroundConfiguration = .clear()
  }

  @objc private func headerPressed(_ gesture: UITapGestureRecognizer) {
    guard let id = gesture.view?.accessibilityIdentifier, !id.isEmpty else { return }
    onRowPress(["id": id])
  }

  private func swipeActions(at indexPath: IndexPath, leading: Bool) -> UISwipeActionsConfiguration? {
    guard let row = row(at: indexPath) else { return nil }
    let actions = leading ? row.leadingActions : row.actions
    if actions.isEmpty { return nil }
    return UISwipeActionsConfiguration(actions: actions.map { action in
      let item = UIContextualAction(style: action.destructive ? .destructive : .normal, title: action.title) { [weak self] _, _, done in
        self?.onRowAction(["id": row.id, "actionId": action.id])
        done(true)
      }
      item.image = action.symbol.isEmpty ? nil : UIImage(systemName: action.symbol)
      if let tint = lodyTint(action.tint) { item.backgroundColor = tint }
      return item
    })
  }

  func row(at index: IndexPath) -> LodyListRow? {
    dataSource.itemIdentifier(for: index).flatMap { rowsByID[$0] }
  }

  func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
    row(at: indexPath)?.action ?? false
  }
  func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
    row(at: indexPath)?.action ?? false
  }
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard let row = row(at: indexPath) else { return }
    if !row.navigates { collectionView.deselectItem(at: indexPath, animated: true) }
    // Outline parents toggle through UIKit; the expansion handlers report the change.
    if row.parent && !row.navigates { return }
    onRowPress(["id": row.id])
  }

  func collectionView(
    _ collectionView: UICollectionView,
    contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
    point: CGPoint
  ) -> UIContextMenuConfiguration? {
    guard let indexPath = indexPaths.first else { return nil }
    return menuConfiguration(at: indexPath)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    contextMenuConfigurationForItemAt indexPath: IndexPath,
    point: CGPoint
  ) -> UIContextMenuConfiguration? {
    menuConfiguration(at: indexPath)
  }

  func collectionView(
    _ collectionView: UICollectionView,
    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
    animator: UIContextMenuInteractionCommitAnimating
  ) {
    guard let id = configuration.identifier as? String else { return }
    animator.addCompletion { [weak self] in
      self?.commitMenu(id)
    }
  }

  private func menuConfiguration(at indexPath: IndexPath) -> UIContextMenuConfiguration? {
    guard let row = row(at: indexPath), !row.menuActions.isEmpty else { return nil }
    let identifier = row.id as NSString
    let previewSession = row.preview == "session"
    let userId = previewUserId
    let workspaceId = previewWorkspaceId
    return UIContextMenuConfiguration(identifier: identifier, previewProvider: {
      guard previewSession else { return nil }
      return ChatTranscriptPreviewController(
        sessionId: row.id,
        title: row.title,
        userId: userId,
        workspaceId: workspaceId
      )
    }, actionProvider: { [weak self] _ in
      self?.menu(for: row)
    })
  }

  private func menu(for row: LodyListRow) -> UIMenu {
    UIMenu(children: row.menuActions.map { action in
      UIAction(
        title: action.title,
        image: action.symbol.isEmpty ? nil : UIImage(systemName: action.symbol),
        attributes: action.destructive ? [.destructive] : []
      ) { [weak self] _ in
        self?.performMenu(row, action)
      }
    })
  }

  private func performMenu(_ row: LodyListRow, _ action: LodyListAction) {
    if action.id == "copyPath" {
      UIPasteboard.general.string = row.subtitle
      return
    }
    onRowAction(["id": row.id, "actionId": action.id])
  }

  private func commitMenu(_ id: String) {
    if id.hasPrefix("toggle:") {
      onRowPress(["id": "project:" + String(id.dropFirst(7))])
      return
    }
    onRowPress(["id": id])
  }

  private func indexPath(for id: String) -> IndexPath? {
    rowsByID.keys.first { $0.row == id }.flatMap { dataSource.indexPath(for: $0) }
  }

  private func deselectOnReturn(animated: Bool, coordinator: UIViewControllerTransitionCoordinator?) {
    guard let index = collection.indexPathsForSelectedItems?.first else { return }
    guard let id = row(at: index)?.id else { return }
    guard let coordinator else {
      collection.deselectItem(at: index, animated: animated)
      return
    }
    let started = coordinator.animate(alongsideTransition: { [weak self] _ in
      guard let self, let current = self.indexPath(for: id) else { return }
      self.collection.deselectItem(at: current, animated: animated)
    }, completion: { [weak self] context in
      guard context.isCancelled, let self, let current = self.indexPath(for: id) else { return }
      self.collection.selectItem(at: current, animated: false, scrollPosition: [])
    })
    if !started { collection.deselectItem(at: index, animated: animated) }
  }

}
