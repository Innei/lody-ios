import UIKit

/// Keep the glass mounted until its material has left, and reverse the same
/// animator when visibility changes mid-flight instead of starting another one.
open class CKGlassSurface: UIVisualEffectView {
  private let glass: UIGlassEffect
  private var motion: UIViewPropertyAnimator?
  private var destination = false
  public private(set) var materialVisible = false
  public var isTransitioning: Bool { motion != nil }
  public var onHidden: (() -> Void)?

  public init(interactive: Bool = false) {
    glass = UIGlassEffect(style: .regular)
    glass.isInteractive = interactive
    super.init(effect: nil)
    isHidden = true
    isUserInteractionEnabled = false
    accessibilityElementsHidden = true
    contentView.alpha = 0
  }

  public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  public func setVisible(_ visible: Bool, animated: Bool = true) {
    let animate = animated && window != nil && UIView.areAnimationsEnabled && !UIAccessibility.isReduceMotionEnabled
    guard visible != materialVisible || (!animate && motion != nil) else { return }
    materialVisible = visible
    isUserInteractionEnabled = visible
    accessibilityElementsHidden = !visible
    if !animate {
      motion?.stopAnimation(true)
      motion = nil
      settle()
      return
    }
    if let motion {
      motion.isReversed = visible != destination
      return
    }
    isHidden = false
    destination = visible
    let animation = UIViewPropertyAnimator(duration: 0.3, curve: .easeInOut) { [weak self] in
      guard let self else { return }
      self.effect = visible ? self.glass : nil
      self.contentView.alpha = visible ? 1 : 0
    }
    animation.addCompletion { [weak self, weak animation] _ in
      guard let self, let animation, self.motion === animation else { return }
      self.motion = nil
      let visible = self.materialVisible
      // UIKit finishes restoring a reversed effect after invoking completion.
      DispatchQueue.main.async { [weak self] in
        guard let self, self.motion == nil, self.materialVisible == visible else { return }
        self.settle()
      }
    }
    motion = animation
    // The owner publishes its new height before the first material frame.
    DispatchQueue.main.async { [weak self, weak animation] in
      guard let self, let animation, self.motion === animation else { return }
      self.window?.layoutIfNeeded()
      animation.startAnimation()
    }
  }

  private func settle() {
    UIView.performWithoutAnimation {
      effect = materialVisible ? glass : nil
      contentView.alpha = materialVisible ? 1 : 0
      isHidden = !materialVisible
    }
    if !materialVisible { onHidden?() }
  }

  open override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { setVisible(materialVisible, animated: false) }
  }
}
