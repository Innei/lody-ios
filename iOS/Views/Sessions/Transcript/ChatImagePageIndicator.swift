import UIKit

final class ChatImagePageIndicator: UILabel {
  var onIncrement: (() -> Void)?
  var onDecrement: (() -> Void)?
  override var accessibilityTraits: UIAccessibilityTraits {
    get { [.adjustable, .staticText] }
    set {}
  }
  override func accessibilityIncrement() { onIncrement?() }
  override func accessibilityDecrement() { onDecrement?() }
}
