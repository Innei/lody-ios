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
}

final class LodyPageController: UIViewController {
  let spec: ShellPageSpec
  var onEvent: ((String, Int) -> Void)?
  private(set) var closed = false

  init(spec: ShellPageSpec) {
    self.spec = spec
    super.init(nibName: nil, bundle: nil)
    title = spec.title
    if spec.headerVariant == "transparent" {
      let appearance = UINavigationBarAppearance()
      appearance.configureWithTransparentBackground()
      navigationItem.standardAppearance = appearance
      navigationItem.scrollEdgeAppearance = appearance
    }
    navigationItem.backButtonDisplayMode = .minimal
  }

  required init?(coder: NSCoder) { nil }

  override func loadView() {
    let surface = LodyShellHost.surface?("LodyPage", ["presentationId": spec.id]) ?? UIView()
    surface.backgroundColor = spec.style == "overFullScreen" ? .clear : .systemBackground
    view = surface
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    navigationController?.setNavigationBarHidden(!spec.headerShown, animated: animated)
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

  func markClosed() {
    guard !closed else { return }
    closed = true
    onEvent?("closed", spec.id)
  }
}
