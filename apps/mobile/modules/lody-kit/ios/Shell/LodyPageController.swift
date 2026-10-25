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
}

final class LodyPageController: UIViewController {
  let spec: ShellPageSpec
  let inSheet: Bool
  var onEvent: ((String, Int) -> Void)?
  private(set) var closed = false
  private var headerHidden: Bool?

  init(spec: ShellPageSpec, inSheet: Bool) {
    self.spec = spec
    self.inSheet = inSheet
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
    view = LodyShellHost.surface?("LodyPage", ["presentationId": spec.id]) ?? UIView()
    updateBackground()
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
