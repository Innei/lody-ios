import AppKit
import LodyData

@MainActor
final class MacDetailController: NSViewController {
  private var current: NSViewController?

  override func loadView() {
    view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
    show(nil)
  }

  func show(_ controller: NSViewController?) {
    current?.view.removeFromSuperview()
    current?.removeFromParent()
    let next = controller ?? MacPlaceholderController(text: String(localized: "mac.workspace.empty", bundle: .lodyMac))
    addChild(next)
    next.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(next.view)
    NSLayoutConstraint.activate([
      next.view.topAnchor.constraint(equalTo: view.topAnchor),
      next.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      next.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      next.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    current = next
  }
}
