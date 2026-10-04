import ExpoModulesCore
import SwiftUI
import UIKit

final class LodySessionShareView: ExpoView {
  let onAction = EventDispatcher()
  private let hosting = UIHostingController(rootView: SessionShareForm(configuration: nil, action: { _, _ in }))
  private weak var scroll: UIScrollView?
  private weak var scrollOwner: UIViewController?
  private weak var sheetOwner: UIViewController?
  private var blocksDismissal = false

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    hosting.view.backgroundColor = .systemGroupedBackground
  }

  func configure(_ json: String) {
    guard let state = try? JSONDecoder().decode(SessionShareForm.Configuration.self, from: Data(json.utf8)) else { return }
    blocksDismissal = state.busy && state.loaded
    hosting.rootView = SessionShareForm(configuration: state) { [weak self] name, value in
      var event: [String: Any] = ["action": name]
      if let value { event["value"] = value }
      self?.onAction(event)
    }
    setNeedsLayout()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil, hosting.parent == nil, let owner = reactViewController() {
      owner.addChild(hosting)
      addSubview(hosting.view)
      hosting.view.frame = bounds
      hosting.didMove(toParent: owner)
    } else if window == nil {
      if let scroll, let scrollOwner { LodyScrollEdges.unbind(scroll, from: scrollOwner) }
      sheetOwner?.isModalInPresentation = false
      sheetOwner = nil
      hosting.willMove(toParent: nil)
      hosting.view.removeFromSuperview()
      hosting.removeFromParent()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    hosting.view.frame = bounds
    guard let owner = hosting.parent else { return }
    if let scroll = findScroll(in: hosting.view) {
      self.scroll = scroll
      scrollOwner = owner
      LodyScrollEdges.navigation(scroll)
      LodyScrollEdges.bind(scroll, to: owner)
    }
    var ancestor: UIViewController? = owner
    while let current = ancestor {
      if current.presentingViewController != nil {
        sheetOwner = current
        current.isModalInPresentation = blocksDismissal
      }
      ancestor = current.parent
    }
  }

  private func findScroll(in view: UIView) -> UIScrollView? {
    if let scroll = view as? UIScrollView { return scroll }
    for child in view.subviews {
      if let scroll = findScroll(in: child) { return scroll }
    }
    return nil
  }
}
