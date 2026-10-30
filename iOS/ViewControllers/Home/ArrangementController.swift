import UIKit

#if compiler(>=6.4)
@available(iOS 27.1, *)
final class ArrangementController: UIArrangementViewController {
  var onLayout: (() -> Void)?

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    onLayout?()
  }
}
#endif
