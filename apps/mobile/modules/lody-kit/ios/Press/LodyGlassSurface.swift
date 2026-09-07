import ExpoModulesCore
import UIKit

/// A standalone glass background: RN cannot render UIGlassEffect, and adding the
/// effect view inside a host that also mounts RN children breaks Fabric's indices.
final class LodyGlassSurface: ExpoView {
  private let effectView = UIVisualEffectView(effect: nil)
  private var radius: CGFloat = 14
  private var tint: UIColor?

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    isUserInteractionEnabled = false
    addSubview(effectView)
    apply()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    effectView.frame = bounds
  }

  func setRadius(_ value: Double) {
    radius = CGFloat(value)
    apply()
  }

  func setTint(_ value: String) {
    tint = lodyTint(value)
    apply()
  }

  private func apply() {
    if #available(iOS 26.0, *) {
      let effect = UIGlassEffect(style: .regular)
      effect.isInteractive = true
      effect.tintColor = tint
      effectView.effect = effect
      effectView.cornerConfiguration = .capsule(maximumRadius: radius)
    } else {
      effectView.effect = UIBlurEffect(style: .systemMaterial)
      effectView.backgroundColor = tint
      effectView.layer.cornerRadius = radius
      effectView.layer.cornerCurve = .continuous
      effectView.clipsToBounds = true
    }
  }
}
