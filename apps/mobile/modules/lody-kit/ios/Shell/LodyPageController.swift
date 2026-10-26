import UIKit

public enum LodyShellHost {
  @MainActor public static var surface: ((String, [AnyHashable: Any]) -> UIView)?
}

struct ShellPageSpec: Decodable {
  var id: Int
  var title: String
  var style: String
  var animation: String
  var dismissible: Bool
  var headerShown: Bool
  var headerVariant: String
  var detents: [Double]?
  var grabber: Bool?
  var initialDetent: Int?
  var container: Int?
  var root: Bool?
  var insertAt: Int?
  var native: String?
  var nativeParams: String?
}

final class LodyPageController: UIViewController {
  let spec: ShellPageSpec
  let inSheet: Bool
  var onEvent: ((String, Int) -> Void)?
  private(set) var closed = false
  private var headerHidden: Bool?
  private var content: UIViewController?

  init(spec: ShellPageSpec, inSheet: Bool, content: UIViewController? = nil) {
    self.spec = spec
    self.inSheet = inSheet
    self.content = content
    super.init(nibName: nil, bundle: nil)
    title = spec.title
    // Declare the bottom-bar policy before UIKit builds its push animator.
    hidesBottomBarWhenPushed = true
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()
    if inSheet, spec.headerVariant == "glass" {
      appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
    }
    navigationItem.standardAppearance = appearance
    navigationItem.scrollEdgeAppearance = appearance
    navigationItem.compactAppearance = appearance
    navigationItem.backButtonDisplayMode = .minimal
    NotificationCenter.default.addObserver(
      self, selector: #selector(appearanceChanged), name: .lodyAppearanceDidChange, object: nil
    )
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit { NotificationCenter.default.removeObserver(self) }

  override func loadView() {
    if let native = content ?? spec.native.flatMap({ LodyNativePages.make($0, params: spec.nativeParams) }) {
      content = nil
      view = UIView()
      embed(native)
      addCloseItem()
    } else {
      view = LodyShellHost.surface?("LodyPage", ["presentationId": spec.id]) ?? UIView()
    }
    updateBackground()
  }

  // React pages add this from ShellPage; native sheet roots without their own items get the same control.
  private func addCloseItem() {
    guard inSheet, spec.style != "push", spec.headerShown,
          navigationItem.rightBarButtonItems?.isEmpty ?? true, navigationItem.leftBarButtonItems?.isEmpty ?? true else { return }
    let close = UIBarButtonItem(primaryAction: UIAction(image: UIImage(systemName: "xmark")) { [weak self] _ in
      self?.dismiss(animated: true)
    })
    close.accessibilityLabel = LodyStrings.text("accessibility.closeSheet", ["title": spec.title])
    navigationItem.rightBarButtonItems = [close]
  }

  private func embed(_ child: UIViewController) {
    addChild(child)
    child.view.frame = view.bounds
    child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(child.view)
    child.didMove(toParent: self)
    // Native lists bind scroll edges to their own controller; the navigation bar reads this one.
    NotificationCenter.default.addObserver(
      self, selector: #selector(childScrollOwnerChanged), name: LodyScrollEdges.ownerChanged, object: child
    )
  }

  @objc private func childScrollOwnerChanged(_ notification: Notification) {
    guard let child = notification.object as? UIViewController else { return }
    setContentScrollView(child.contentScrollView(for: .top), for: .top)
    setContentScrollView(child.contentScrollView(for: .bottom), for: .bottom)
  }

  override func setToolbarItems(_ toolbarItems: [UIBarButtonItem]?, animated: Bool) {
    hidesBottomBarWhenPushed = toolbarItems?.isEmpty ?? true
    super.setToolbarItems(toolbarItems, animated: animated)
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(headerHidden ?? !spec.headerShown, animated: animated)
    updateBackground()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    onEvent?("focus", spec.id)
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    onEvent?("blur", spec.id)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
      markClosed()
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (page: LodyPageController, _: UITraitCollection) in
      page.updateBackground()
    }
  }

  func setHeaderHidden(_ value: Bool?) {
    guard value != headerHidden else { return }
    headerHidden = value
    guard let navigationController, navigationController.topViewController === self else { return }
    navigationController.setNavigationBarHidden(value ?? !spec.headerShown, animated: false)
  }

  func markClosed() {
    guard !closed else { return }
    closed = true
    onEvent?("closed", spec.id)
  }

  @objc private func appearanceChanged() {
    view.backgroundColor = nil
    updateBackground()
  }

  private func updateBackground() {
    guard isViewLoaded else { return }
    let container = navigationController?.modalPresentationStyle
    let regular = (view.window?.traitCollection ?? traitCollection).horizontalSizeClass == .regular
    let overlay = spec.style == "overFullScreen" || container == .overFullScreen
    let compactSheet = inSheet && !regular && (container == .formSheet || container == .pageSheet)
    view.backgroundColor = overlay || compactSheet ? .clear : .lodyGroupedBackground
  }
}
