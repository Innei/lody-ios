import UIKit

final class ChatComposerLiquidGlassSurfaceLayout: ChatComposerSurfaceLayout {
  static let sheetCornerRadius: CGFloat = 28
  // The iOS 26 keyboard has rounded top corners; material continuing behind it keeps the sheet from showing a seam there.
  static let sheetBleed: CGFloat = 40
  static let capsuleInset: CGFloat = 20
  static let capsuleBottom: CGFloat = 8
  static let capsuleRadius: CGFloat = 24
  private let inputSurface: UIVisualEffectView
  private let pill: [NSLayoutConstraint]
  private let sheet: [NSLayoutConstraint]
  private var isFocused = false
  private var collapse: CGFloat = 0

  init(container: UIVisualEffectView, inputSurface: UIVisualEffectView) {
    self.inputSurface = inputSurface
    let containerEffect = UIGlassContainerEffect()
    containerEffect.spacing = 8
    container.effect = containerEffect
    let glass = UIGlassEffect(style: .regular)
    glass.isInteractive = true
    inputSurface.effect = glass
    let host = container.contentView
    pill = [
      inputSurface.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: Self.capsuleInset),
      inputSurface.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -Self.capsuleInset),
      inputSurface.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -Self.capsuleBottom),
    ]
    sheet = [
      inputSurface.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      inputSurface.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      inputSurface.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: Self.sheetBleed),
    ]
  }

  func activate() {
    NSLayoutConstraint.activate(pill)
    applyCorners()
  }

  func update(isFocused: Bool) {
    guard self.isFocused != isFocused else { return }
    self.isFocused = isFocused
    collapse = 0
    applySheet(collapse: 0)
    NSLayoutConstraint.deactivate(isFocused ? pill : sheet)
    NSLayoutConstraint.activate(isFocused ? sheet : pill)
    applyCorners()
  }

  func update(collapse progress: CGFloat) {
    guard isFocused, collapse != progress else { return }
    collapse = progress
    applySheet(collapse: progress)
    guard progress > 0 else {
      applyCorners()
      return
    }
    let top = UICornerRadius.fixed(Self.sheetCornerRadius + (Self.capsuleRadius - Self.sheetCornerRadius) * progress)
    let bottom = UICornerRadius.fixed(Self.capsuleRadius * progress)
    inputSurface.cornerConfiguration = .corners(topLeftRadius: top, topRightRadius: top, bottomLeftRadius: bottom, bottomRightRadius: bottom)
  }

  private func applySheet(collapse progress: CGFloat) {
    sheet[0].constant = Self.capsuleInset * progress
    sheet[1].constant = -Self.capsuleInset * progress
    sheet[2].constant = Self.sheetBleed * (1 - progress) - Self.capsuleBottom * progress
  }

  private func applyCorners() {
    if isFocused {
      let top = UICornerRadius.fixed(Self.sheetCornerRadius)
      inputSurface.cornerConfiguration = .corners(topLeftRadius: top, topRightRadius: top, bottomLeftRadius: .fixed(0), bottomRightRadius: .fixed(0))
    } else {
      inputSurface.cornerConfiguration = .capsule(maximumRadius: 24)
    }
  }
}
