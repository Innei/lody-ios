import ExpoModulesCore
import UIKit

struct LodyListAction: Record {
  @Field var id: String = ""
  @Field var title: String = ""
  @Field var symbol: String = ""
  @Field var tint: String = ""
  @Field var destructive: Bool = false
}

struct LodyListRow: Record {
  @Field var id: String = ""
  @Field var title: String = ""
  @Field var subtitle: String = ""
  @Field var value: String = ""
  @Field var image: String = ""
  @Field var imageTint: String = ""
  @Field var subtitleMono: Bool = false
  @Field var unread: Bool = false
  @Field var badge: String = ""
  @Field var diff: [String: Int] = [:]
  @Field var action: Bool = false
  @Field var navigates: Bool = false
  @Field var disclosure: Bool = false
  @Field var destructive: Bool = false
  @Field var actions: [LodyListAction] = []
  @Field var leadingActions: [LodyListAction] = []
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
  private var transparent = false
  private var contentStyle = false
  private var rowsByID: [ListItemID: LodyListRow] = [:]
  private var dataSource: UICollectionViewDiffableDataSource<String, ListItemID>!

  private static let restingCard = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
      : .white
  }
  private static let selectedCard = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
      : UIColor(red: 0.898, green: 0.898, blue: 0.918, alpha: 1)
  }

  private let registration = UICollectionView.CellRegistration<UICollectionViewListCell, LodyListRow> { cell, _, row in
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
    if !row.image.isEmpty {
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
    cell.accessibilityIdentifier = row.id
    cell.accessibilityTraits = row.action ? .button : .staticText
  }

  private let sessionRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, LodyListRow> { cell, _, row in
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

  private let headerRegistration = UICollectionView.SupplementaryRegistration<SectionSupplementaryCell>(
    elementKind: UICollectionView.elementKindSectionHeader
  ) { _, _, _ in }

  private let footerRegistration = UICollectionView.SupplementaryRegistration<SectionSupplementaryCell>(
    elementKind: UICollectionView.elementKindSectionFooter
  ) { _, _, _ in }

  required init(appContext: AppContext? = nil) {
    var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
    configuration.headerMode = .supplementary
    configuration.footerMode = .supplementary
    collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
    super.init(appContext: appContext)
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
    collection.delegate = self
    configuration.leadingSwipeActionsConfigurationProvider = { [weak self] indexPath in
      self?.swipeActions(at: indexPath, leading: true)
    }
    configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
      self?.swipeActions(at: indexPath, leading: false)
    }
    collection.setCollectionViewLayout(UICollectionViewCompositionalLayout.list(using: configuration), animated: false)
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

  func setContentStyle(_ value: Bool) {
    guard value != contentStyle else { return }
    contentStyle = value
    collection.reloadData()
  }

  /// A sheet paints its own material. Dropping the list's ground lets that
  /// material show between groups; cells take `lodyOpaqueCard` so rows still
  /// read as cards.
  func setTransparent(_ value: Bool) {
    guard value != transparent else { return }
    transparent = value
    collection.backgroundColor = value ? .clear : .systemGroupedBackground
    collection.reloadData()
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

  private func cell(in collectionView: UICollectionView, at indexPath: IndexPath, row: LodyListRow) -> UICollectionViewListCell {
    let sessionRow = contentStyle && (!row.value.isEmpty || !row.badge.isEmpty)
    let cell = collectionView.dequeueConfiguredReusableCell(using: sessionRow ? sessionRegistration : registration, for: indexPath, item: row)
    cell.configurationUpdateHandler = nil
    cell.automaticallyUpdatesBackgroundConfiguration = true
    if contentStyle {
      if var content = cell.contentConfiguration as? UIListContentConfiguration {
        content.textProperties.numberOfLines = 2
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .footnote)
        content.directionalLayoutMargins = .init(top: 12, leading: 22, bottom: 12, trailing: 22)
        cell.contentConfiguration = content
      }
      cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
    } else if transparent {
      // A static backgroundConfiguration freezes the cell's appearance, so the
      // highlighted and selected states stop rendering. The update handler
      // keeps UIKit's state resolution and only forces the resting color to be
      // opaque, which the glass sheet context otherwise makes translucent.
      cell.configurationUpdateHandler = { cell, state in
        var background = UIBackgroundConfiguration.listGroupedCell().updated(for: state)
        background.backgroundColor = state.isHighlighted || state.isSelected
          ? LodyGroupedList.selectedCard
          : LodyGroupedList.restingCard
        cell.backgroundConfiguration = background
      }
    } else {
      cell.backgroundConfiguration = UIBackgroundConfiguration.listGroupedCell()
    }
    return cell
  }

  private func section(at index: Int) -> LodyListSection? {
    let identifiers = dataSource.snapshot().sectionIdentifiers
    guard identifiers.indices.contains(index) else { return nil }
    return sections.first { $0.id == identifiers[index] }
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
        view.accessibilityValue = expanded ? "已展开" : "已折叠"
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

  private func row(at index: IndexPath) -> LodyListRow? {
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
    onRowPress(["id": row.id])
  }

  private func indexPath(for id: String) -> IndexPath? {
    for (section, entry) in sections.enumerated() {
      if let item = entry.rows.firstIndex(where: { $0.id == id }) {
        return IndexPath(item: item, section: section)
      }
    }
    return nil
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
