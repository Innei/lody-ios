import ExpoModulesCore
import UIKit

final class LodySymbolButton: ExpoView {
  let onSymbolPress = EventDispatcher()
  let onSymbolLongPress = EventDispatcher()
  private let button = UIButton(type: .system)
  private let hold = UILongPressGestureRecognizer()
  private var symbol = "circle"
  private var prominent = false

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    button.addTarget(self, action: #selector(pressed), for: .primaryActionTriggered)
    hold.addTarget(self, action: #selector(held))
    hold.minimumPressDuration = 0.6
    hold.isEnabled = false
    button.addGestureRecognizer(hold)
    button.tintColor = .label
    addSubview(button)
    apply()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    button.frame = bounds
  }

  func setSymbol(_ value: String) {
    let previous = symbol
    symbol = value
    apply(byLayer: previous + ".fill" == value || value + ".fill" == previous)
  }

  func setAccessibilityName(_ value: String) {
    button.accessibilityLabel = value
  }

  func setProminent(_ value: Bool) {
    prominent = value
    apply()
  }

  func setDisabled(_ value: Bool) {
    button.isEnabled = !value
  }

  func setTint(_ value: String) {
    button.tintColor = lodyTint(value) ?? .label
  }

  func setLongPress(_ value: Bool) {
    hold.isEnabled = value
  }

  private func apply(byLayer: Bool = false) {
    var configuration = prominent
      ? UIButton.Configuration.filled()
      : UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: symbol)
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      textStyle: prominent ? .body : .title3,
      scale: .medium
    )
    configuration.contentInsets = .zero
    if prominent { configuration.cornerStyle = .capsule }
    if button.configuration?.image != nil {
      configuration.symbolContentTransition = .init(byLayer ? .replace.byLayer : .replace)
    }
    button.configuration = configuration
  }

  @objc private func pressed() {
    onSymbolPress([:])
  }

  @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began else { return }
    UISelectionFeedbackGenerator().selectionChanged()
    onSymbolLongPress([:])
  }
}
