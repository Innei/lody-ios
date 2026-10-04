import UIKit

@MainActor
final class AccentColorPicker: NSObject, UIColorPickerViewControllerDelegate {
  private weak var picker: UIColorPickerViewController?
  var onChange: ((String) -> Void)?

  func present(from controller: UIViewController, title: String) {
    guard picker?.presentingViewController == nil else { return }
    let picker = UIColorPickerViewController()
    picker.title = title
    picker.supportsAlpha = false
    picker.selectedColor = LodyAccentChoice.current.color
    picker.delegate = self
    self.picker = picker
    controller.present(picker, animated: true)
  }

  func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
    let value = LodyAccentChoice.hex(color)
    LodyAccentChoice.save(value)
    onChange?(value)
  }

  func dismiss() {
    picker?.delegate = nil
    picker?.dismiss(animated: false)
    picker = nil
    onChange = nil
  }
}
