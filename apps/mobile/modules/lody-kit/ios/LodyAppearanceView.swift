import ExpoModulesCore
import UIKit

class LodyAppearanceView: ExpoView {
  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(lodyAppearanceDidChange),
      name: .lodyAppearanceDidChange,
      object: nil
    )
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  @objc func lodyAppearanceDidChange() {}
}
