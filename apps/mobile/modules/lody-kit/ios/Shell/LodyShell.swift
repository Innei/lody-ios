import UIKit

@MainActor
final class LodyShell {
  static let shared = LodyShell()
  nonisolated static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--uikit-shell") }

  var emit: ((String, Int) -> Void)?
  private var navigation: UINavigationController?
  private var pages: [Int: WeakPage] = [:]

  func present(_ json: String) {
    guard let spec = try? JSONDecoder().decode(ShellPageSpec.self, from: Data(json.utf8)) else { return }
    let page = LodyPageController(spec: spec)
    page.onEvent = { [weak self] type, id in self?.event(type, id) }
    pages[spec.id] = WeakPage(value: page)
    if spec.root == true {
      setRoot(page)
    } else if spec.style == "push" {
      let target = spec.container.flatMap { pages[$0]?.value?.navigationController } ?? navigation
      target?.pushViewController(page, animated: spec.animation != "none")
    } else {
      presentModal(page)
    }
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
      navigation.setViewControllers([page], animated: false)
      scheduleSweep()
      return
    }
    guard let host = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first
    else { return }
    let navigation = UINavigationController(rootViewController: page)
    host.addChild(navigation)
    navigation.view.frame = host.view.bounds
    navigation.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    host.view.addSubview(navigation.view)
    navigation.didMove(toParent: host)
    self.navigation = navigation
  }

  private func presentModal(_ page: LodyPageController) {
    let spec = page.spec
    let container = UINavigationController(rootViewController: page)
    container.setNavigationBarHidden(!spec.headerShown, animated: false)
    container.modalPresentationStyle = Self.modalStyle(spec.style)
    if spec.style == "overFullScreen" { container.view.backgroundColor = .clear }
    if spec.animation == "fade" { container.modalTransitionStyle = .crossDissolve }
    container.isModalInPresentation = !spec.dismissible
    if let sheet = container.sheetPresentationController, spec.style == "formSheet" || spec.style == "pageSheet" {
      Self.configure(sheet, spec)
    }
    topController()?.present(container, animated: spec.animation != "none")
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
