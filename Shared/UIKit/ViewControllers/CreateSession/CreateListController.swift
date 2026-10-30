import LodyCore
import UIKit

@MainActor
class CreateListController: UIViewController {
  let list = LodyGroupedList(frame: .zero)

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.backButtonDisplayMode = .minimal
    list.frame = view.bounds
    list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    list.setTransparent(true)
    list.setGrouped(true)
    list.forwarded = { [weak self] name, body in self?.event(name, body) }
    view.addSubview(list)
  }

  func event(_ name: String, _ body: [String: Any]) {}
}
