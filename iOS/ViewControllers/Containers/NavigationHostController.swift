import UIKit

final class NavigationHostController: UIViewController {
  private let navigation: UINavigationController
  init(_ navigation: UINavigationController) {
    self.navigation = navigation
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError() }
  override var childForStatusBarStyle: UIViewController? { navigation }
  override func viewDidLoad() {
    super.viewDidLoad()
    addChild(navigation)
    navigation.view.frame = view.bounds
    navigation.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(navigation.view)
    navigation.didMove(toParent: self)
  }
  func releaseNavigation() {
    navigation.willMove(toParent: nil)
    navigation.view.removeFromSuperview()
    navigation.removeFromParent()
  }
}
