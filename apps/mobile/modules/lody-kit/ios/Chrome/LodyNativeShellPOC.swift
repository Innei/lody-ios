#if DEBUG
import ExpoModulesCore
import React
import UIKit

final class LodyNativePagePOC: ExpoView {
  var pageKind = "root"
  private var touches: UIGestureRecognizer?
  private var publishedSize = CGSize.zero
  private var hostedRect: CGRect?

  // Fabric still commits the logical child's (0, 0) origin after sizing.
  // UIKit owns this reparented view's physical placement, including safe areas.
  override var center: CGPoint {
    get { super.center }
    set { super.center = hostedRect.map { CGPoint(x: $0.midX, y: $0.midY) } ?? newValue }
  }

  override var bounds: CGRect {
    get { super.bounds }
    set { super.bounds = hostedRect.map { CGRect(origin: .zero, size: $0.size) } ?? newValue }
  }

  func place(in rect: CGRect) {
    hostedRect = rect
    frame = rect
    if publishedSize != rect.size {
      publishedSize = rect.size
      setViewSize(rect.size)
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      if let touches { LodyNativeShellTouchPOC.detach(touches, from: self) }
      touches = nil
    } else if touches == nil {
      touches = LodyNativeShellTouchPOC.attach(to: self)
    }
  }
}

private final class NativePOCContent: UIView {
  let page: LodyNativePagePOC
  init(page: LodyNativePagePOC) {
    self.page = page
    super.init(frame: .zero)
    clipsToBounds = true
    addSubview(page)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func layoutSubviews() {
    super.layoutSubviews()
    page.place(in: bounds)
  }
}

private final class NativePOCPageController: UIViewController, UISearchResultsUpdating {
  let page: LodyNativePagePOC
  weak var shell: LodyNativeShellPOC?

  init(page: LodyNativePagePOC, shell: LodyNativeShellPOC) {
    self.page = page
    self.shell = shell
    super.init(nibName: nil, bundle: nil)
    title = ["root": "Native Sidebar", "project": "Project", "detail": "React Detail"][page.pageKind]
    if page.pageKind == "root" {
      navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak shell] _ in
        shell?.close()
      })
      let search = UISearchController(searchResultsController: nil)
      search.searchBar.searchTextField.accessibilityIdentifier = "poc-search"
      search.obscuresBackgroundDuringPresentation = false
      search.searchResultsUpdater = self
      navigationItem.searchController = search
      navigationItem.hidesSearchBarWhenScrolling = false
      navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Project", primaryAction: UIAction { [weak self] _ in
        self?.navigationItem.searchController?.isActive = false
        self?.shell?.onAction(["action": "openProject"])
      })
    } else {
      navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", primaryAction: UIAction { [weak self] _ in
        self?.view.endEditing(true)
      })
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func loadView() {
    view = UIView()
    view.backgroundColor = .systemBackground
    let content = NativePOCContent(page: page)
    content.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(content)
    let bottom = content.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
    bottom.priority = .defaultHigh
    NSLayoutConstraint.activate([
      content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
      content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
      content.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor),
      bottom,
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if let scroll = findScroll(page) {
      setContentScrollView(scroll, for: .top)
      scroll.topEdgeEffect.style = .soft
      scroll.bottomEdgeEffect.style = .soft
    }
  }

  private func findScroll(_ view: UIView) -> UIScrollView? {
    if let scroll = view as? UIScrollView { return scroll }
    for child in view.subviews {
      if let scroll = findScroll(child) { return scroll }
    }
    return nil
  }

  func updateSearchResults(for searchController: UISearchController) {
    shell?.onAction(["action": "search", "text": searchController.searchBar.text ?? ""])
  }
}

private final class NativeCollectionPOCController: UICollectionViewController, UISearchResultsUpdating {
  private var source: UICollectionViewDiffableDataSource<Int, Int>!
  private weak var shell: LodyNativeShellPOC?
  private let session: Int?

  init(shell: LodyNativeShellPOC, session: Int? = nil) {
    self.shell = shell
    self.session = session
    var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
    configuration.backgroundColor = .systemBackground
    super.init(collectionViewLayout: UICollectionViewCompositionalLayout.list(using: configuration))
    title = session.map { "Session \($0)" } ?? "Collections"
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    // UICollectionViewController owns the full viewport; UIKit reserves the initial
    // header space with insets, so rows can scroll behind both navigation and search.
    collectionView.accessibilityIdentifier = session == nil ? "poc-native-collection" : "poc-native-session"
    collectionView.contentInsetAdjustmentBehavior = .automatic
    collectionView.keyboardDismissMode = .onDrag
    setContentScrollView(collectionView, for: .top)
    collectionView.topEdgeEffect.style = .soft
    collectionView.bottomEdgeEffect.style = .soft
    let search = UISearchController(searchResultsController: nil)
    search.obscuresBackgroundDuringPresentation = false
    search.hidesNavigationBarDuringPresentation = false
    search.searchResultsUpdater = self
    search.searchBar.searchTextField.accessibilityIdentifier = "poc-collection-search"
    navigationItem.searchController = search
    navigationItem.preferredSearchBarPlacement = .stacked
    navigationItem.hidesSearchBarWhenScrolling = false
    if session == nil {
      navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
        self?.shell?.close()
      })
    }
    let isRoot = session == nil
    let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { cell, _, number in
      var content = cell.defaultContentConfiguration()
      content.text = isRoot ? "Session \(number)" : "Message \(number)"
      content.secondaryText = "Native collection row · \(number)"
      content.image = UIImage(systemName: isRoot ? "folder" : "text.bubble")
      content.imageProperties.tintColor = .systemBlue
      cell.contentConfiguration = content
      cell.accessibilityIdentifier = "poc-collection-row-\(number)"
      cell.accessories = isRoot ? [.disclosureIndicator()] : []
    }
    source = UICollectionViewDiffableDataSource<Int, Int>(collectionView: collectionView) { collection, path, number in
      collection.dequeueConfiguredReusableCell(using: registration, for: path, item: number)
    }
    applySearch("")
  }

  private func applySearch(_ query: String) {
    let prefix = session == nil ? "Session" : "Message"
    var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
    snapshot.appendSections([0])
    snapshot.appendItems((1...80).filter { query.isEmpty || "\(prefix) \($0)".localizedCaseInsensitiveContains(query) })
    source.apply(snapshot, animatingDifferences: false)
  }

  func updateSearchResults(for searchController: UISearchController) {
    guard source != nil else { return }
    applySearch(searchController.searchBar.text ?? "")
  }

  override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    guard session == nil, let shell, let number = source.itemIdentifier(for: indexPath) else {
      collectionView.deselectItem(at: indexPath, animated: true)
      return
    }
    navigationItem.searchController?.isActive = false
    navigationController?.pushViewController(NativeCollectionPOCController(shell: shell, session: number), animated: true)
  }
}

// ponytail: fixed root/project/detail roles for this POC; generalize only after migration approval.
final class LodyNativeShellPOC: ExpoView, UINavigationControllerDelegate {
  let onAction = EventDispatcher()
  var collectionSidebar = false {
    didSet {
      if collectionSidebar && !oldValue {
        primary.setViewControllers([NativeCollectionPOCController(shell: self)], animated: false)
      }
    }
  }
  private let split = UISplitViewController(style: .doubleColumn)
  private let primary = UINavigationController()
  private let secondary = UINavigationController()
  private var pages: [String: NativePOCPageController] = [:]
  private var cancelledPops = 0
  private var closed = false

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    split.primaryBackgroundStyle = .none
    split.preferredDisplayMode = .oneBesideSecondary
    split.showsSecondaryOnlyButton = true
    split.modalPresentationStyle = .fullScreen
    split.view.accessibilityIdentifier = "native-shell-ready"
    split.setViewController(primary, for: .primary)
    split.setViewController(secondary, for: .secondary)
    primary.delegate = self
  }

  override func mountChildComponentView(_ child: UIView, index: Int) {
    guard let page = child as? LodyNativePagePOC else { return }
    let controller = NativePOCPageController(page: page, shell: self)
    pages[page.pageKind] = controller
    switch page.pageKind {
    case "root": primary.setViewControllers([controller], animated: false)
    case "detail": secondary.setViewControllers([controller], animated: false)
    case "project": primary.pushViewController(controller, animated: window != nil)
    default: break
    }
    attach()
  }

  override func unmountChildComponentView(_ child: UIView, index: Int) {
    guard let page = child as? LodyNativePagePOC else { return }
    if let controller = pages.removeValue(forKey: page.pageKind),
       let navigation = controller.navigationController {
      navigation.setViewControllers(navigation.viewControllers.filter { $0 !== controller }, animated: false)
    }
    page.removeFromSuperview()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    attach()
  }

  private func attach() {
    guard !closed, window != nil, split.presentingViewController == nil,
          let owner = reactViewController(), owner.presentedViewController == nil else { return }
    // A native shell lives outside the RN surface. Each page is a React touch/layout
    // root, like RN Modal, rather than a reparented child with two coordinate spaces.
    owner.present(split, animated: false)
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    if superview == nil {
      split.dismiss(animated: false)
    }
  }

  func close() {
    closed = true
    split.dismiss(animated: true) { [weak self] in self?.onAction(["action": "close"]) }
  }

  func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
    navigationController.transitionCoordinator?.notifyWhenInteractionChanges { [weak self] context in
      if context.isCancelled {
        self?.cancelledPops += 1
        self?.onAction(["action": "cancelledPop", "count": self?.cancelledPops ?? 0])
      }
    }
  }

  func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
    if let project = pages["project"], !navigationController.viewControllers.contains(project) {
      onAction(["action": "projectClosed"])
    }
  }
}
#endif
