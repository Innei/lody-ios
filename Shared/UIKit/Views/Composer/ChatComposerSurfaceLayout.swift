import UIKit

@MainActor
protocol ChatComposerSurfaceLayout: AnyObject {
  func activate()
  func update(isFocused: Bool)
  func update(collapse progress: CGFloat)
  func completeTransition()
}

extension ChatComposerSurfaceLayout {
  func completeTransition() {}
}
