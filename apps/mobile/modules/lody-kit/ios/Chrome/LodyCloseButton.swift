import ExpoModulesCore
import UIKit

final class LodyCloseButton: ExpoView {
  let onClose = EventDispatcher()
  private let button = UIButton(type: .close)

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    button.accessibilityLabel = LodyStrings.text("native.close")
    button.addTarget(self, action: #selector(close), for: .primaryActionTriggered)
    addSubview(button)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    button.frame = bounds
  }

  func setAccessibilityName(_ label: String) {
    button.accessibilityLabel = label
  }

  @objc private func close() {
    onClose([:])
  }
}
