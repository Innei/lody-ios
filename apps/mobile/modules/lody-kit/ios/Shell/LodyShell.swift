import UIKit

@MainActor
final class LodyShell {
  static let shared = LodyShell()

  var emit: ((String, Int) -> Void)?
  private var navigation: UINavigationController?
  private var pages: [Int: WeakPage] = [:]
  private let delegate = ShellNavigationDelegate()

  func present(_ json: String) {
    guard let spec = try? JSONDecoder().decode(ShellPageSpec.self, from: Data(json.utf8)) else { return }
    let container = spec.container.flatMap { pages[$0]?.value?.navigationController }
    let page = LodyPageController(spec: spec, inSheet: spec.root != true && (spec.style != "push" || container != nil))
    page.onEvent = { [weak self, weak page] type, id in
      guard let self, let page, self.pages[id]?.value === page else { return }
      self.event(type, id)
    }
    if spec.root == true {
      // A reloaded JS runtime restarts presentation ids; earlier pages must not report into it.
      pages = [spec.id: WeakPage(value: page)]
      setRoot(page)
    } else if spec.style == "push" {
      pages[spec.id] = WeakPage(value: page)
      push(page, on: container ?? navigation)
    } else {
      pages[spec.id] = WeakPage(value: page)
      presentModal(page)
    }
  }

  func pushNative(_ id: String, title: String, from source: UIViewController) {
    guard let target = source.navigationController else { return }
    let spec = ShellPageSpec(
      id: 0, title: title, style: "push", animation: "slide", dismissible: true, headerShown: true,
      headerVariant: "transparent", native: id
    )
    push(LodyPageController(spec: spec, inSheet: target !== navigation), on: target)
  }

  private func push(_ page: LodyPageController, on target: UINavigationController?) {
    guard let target else { return }
    if let transition = target.transitionCoordinator {
      transition.animate(alongsideTransition: nil) { [weak self, weak target] _ in
        guard !page.closed else { return }
        self?.push(page, on: target)
      }
      return
    }
    if let index = page.spec.insertAt, index < target.viewControllers.count {
      var stack = target.viewControllers
      stack.insert(page, at: max(1, index))
      target.setViewControllers(stack, animated: false)
      return
    }
    NotificationCenter.default.post(name: Notification.Name("RNSScreenWillPush"), object: page)
    target.pushViewController(page, animated: page.spec.animation != "none")
  }

  func setStack(_ ids: [Int]) {
    guard let navigation else { return }
    if let transition = navigation.transitionCoordinator {
      transition.animate(alongsideTransition: nil) { [weak self] _ in self?.setStack(ids) }
      return
    }
    let stack: [UIViewController] = ids.compactMap { pages[$0]?.value }
      .filter { $0.navigationController === navigation && !$0.closed }
    guard stack.first === navigation.viewControllers.first, stack != navigation.viewControllers else { return }
    navigation.setViewControllers(stack, animated: false)
    scheduleSweep()
  }

  func close(_ id: Int) {
    guard let page = pages[id]?.value, !page.closed else { return }
    guard let container = page.navigationController else {
      page.markClosed()
      return
    }
    if container !== navigation, container.viewControllers.first === page {
      container.presentingViewController?.dismiss(animated: true) { [weak self] in self?.sweep() }
      return
    }
    guard let index = container.viewControllers.firstIndex(of: page), index > 0 else { return }
    if container.presentedViewController != nil { container.dismiss(animated: false) }
    container.popToViewController(container.viewControllers[index - 1], animated: true)
    scheduleSweep()
  }

  func popToRoot() {
    guard let navigation else { return }
    if navigation.presentedViewController != nil {
      navigation.dismiss(animated: true) { [weak self] in self?.sweep() }
    }
    navigation.popToRootViewController(animated: true)
    scheduleSweep()
  }

  private func setRoot(_ page: LodyPageController) {
    if let navigation {
      // A new root comes from a reloaded runtime: retire the old stack so its surfaces stop with it.
      if navigation.presentedViewController != nil { navigation.dismiss(animated: false) }
      navigation.willMove(toParent: nil)
      navigation.view.removeFromSuperview()
      navigation.removeFromParent()
      self.navigation = nil
    }
    guard let host = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
    else { return }
    let navigation = UINavigationController(rootViewController: page)
    navigation.delegate = delegate
    host.addChild(navigation)
    navigation.view.frame = host.view.bounds
    navigation.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.view.addSubview(navigation.view)
    navigation.didMove(toParent: host)
    self.navigation = navigation
  }

  private func presentModal(_ page: LodyPageController) {
    let top = topController()
    let settling = top?.presentedViewController ?? (top?.isBeingPresented == true ? top : nil)
    if let transition = settling?.transitionCoordinator {
      transition.animate(alongsideTransition: nil) { [weak self] _ in
        guard !page.closed else { return }
        self?.presentModal(page)
      }
      return
    }
    guard let presenter = top else { return }
    let spec = page.spec
    let container = UINavigationController(rootViewController: page)
    container.delegate = delegate
    container.setNavigationBarHidden(!spec.headerShown, animated: false)
    container.modalPresentationStyle = Self.modalStyle(spec.style)
    if spec.style == "overFullScreen" { container.view.backgroundColor = .clear }
    if spec.animation == "fade" { container.modalTransitionStyle = .crossDissolve }
    container.isModalInPresentation = !spec.dismissible
    if let sheet = container.sheetPresentationController, spec.style == "formSheet" || spec.style == "pageSheet" {
      Self.configure(sheet, spec)
    }
    NotificationCenter.default.post(
      name: Notification.Name("RNSScreenWillPresent"), object: container, userInfo: ["presenter": presenter]
    )
    presenter.present(container, animated: spec.animation != "none")
  }

  private func topController() -> UIViewController? {
    var top: UIViewController? = navigation
    while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
    return top
  }

  private func event(_ type: String, _ id: Int) {
    emit?(type, id)
    guard type == "closed" else { return }
    pages[id] = nil
    scheduleSweep()
  }

  private func scheduleSweep() {
    DispatchQueue.main.async { [weak self] in self?.sweep() }
  }

  private func sweep() {
    for (id, entry) in pages {
      guard let page = entry.value else {
        pages[id] = nil
        emit?("closed", id)
        continue
      }
      if !page.closed, !alive(page) { page.markClosed() }
    }
  }

  private func alive(_ page: LodyPageController) -> Bool {
    guard let container = page.navigationController else { return false }
    return container === navigation || container.presentingViewController != nil
  }

  private static func modalStyle(_ style: String) -> UIModalPresentationStyle {
    switch style {
    case "fullScreen": .fullScreen
    case "overFullScreen": .overFullScreen
    case "formSheet": .formSheet
    default: .pageSheet
    }
  }

  private static func configure(_ sheet: UISheetPresentationController, _ spec: ShellPageSpec) {
    sheet.prefersGrabberVisible = spec.grabber ?? false
    guard let fractions = spec.detents, !fractions.isEmpty else { return }
    let detents = fractions.map { fraction -> UISheetPresentationController.Detent in
      if fraction >= 1 { return .large() }
      return .custom(identifier: .init("fraction-\(fraction)")) { $0.maximumDetentValue * fraction }
    }
    sheet.detents = detents
    if let index = spec.initialDetent {
      let resolved = index < 0 ? detents.count - 1 : min(index, detents.count - 1)
      sheet.selectedDetentIdentifier = detents[resolved].identifier
    }
  }
}

private struct WeakPage {
  weak var value: LodyPageController?
}

private final class ShellNavigationDelegate: NSObject, UINavigationControllerDelegate {
  func navigationController(
    _ navigationController: UINavigationController,
    didShow viewController: UIViewController,
    animated: Bool
  ) {
    // Reconcile only after UIKit settles, including a cancelled interactive pop.
    navigationController.setToolbarHidden(viewController.toolbarItems?.isEmpty ?? true, animated: false)
  }
}
