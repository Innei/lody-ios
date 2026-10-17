import ExpoModulesCore
import UIKit

final class LodyLayoutProbe: ExpoView {
  let onTraits = EventDispatcher()
  private var lastReport = ""

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    isUserInteractionEnabled = false
    registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (probe: LodyLayoutProbe, _) in
      probe.report()
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    report()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    report()
  }

  private func report() {
    guard let window else { return }
    let size = window.bounds.size
    guard size.width > 0, size.height > 0 else { return }
    let horizontal = window.traitCollection.horizontalSizeClass == .regular ? "regular" : "compact"
    let key = "\(horizontal):\(size.width)x\(size.height)"
    guard key != lastReport else { return }
    lastReport = key
    onTraits(["horizontal": horizontal, "width": size.width, "height": size.height])
  }
}
