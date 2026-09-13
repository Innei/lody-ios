import UIKit

final class ChatComposerLiquidGlassSurfaceLayout: ChatComposerSurfaceLayout {
  private let inputSurface: UIVisualEffectView
  private let attachSurface: UIVisualEffectView
  private let attachButton: UIButton
  private let glyph = UIImageView()
  private let restingImage: UIImage?
  private let focusedImage = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular))
  private let separateAttachLeading: NSLayoutConstraint
  private let focusedAttachLeading: NSLayoutConstraint
  private let separateInputLeading: NSLayoutConstraint
  private let focusedInputLeading: NSLayoutConstraint
  private let attachBottom: NSLayoutConstraint
  private var buttonConstraints: [NSLayoutConstraint] = []
  private var isFocused = false

  init(
    container: UIVisualEffectView,
    inputSurface: UIVisualEffectView,
    attachSurface: UIVisualEffectView,
    attachButton: UIButton
  ) {
    self.inputSurface = inputSurface
    self.attachSurface = attachSurface
    self.attachButton = attachButton
    restingImage = attachButton.image(for: .normal)
    attachButton.setImage(nil, for: .normal)
    attachButton.configuration?.image = nil
    glyph.image = restingImage
    glyph.translatesAutoresizingMaskIntoConstraints = false
    glyph.tintColor = attachButton.tintColor
    glyph.isUserInteractionEnabled = false
    glyph.isAccessibilityElement = false
    glyph.accessibilityIdentifier = "session-attach-glyph"
    attachButton.addSubview(glyph)
    NSLayoutConstraint.activate([
      glyph.centerXAnchor.constraint(equalTo: attachButton.centerXAnchor),
      glyph.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor),
    ])

    let containerEffect = UIGlassContainerEffect()
    containerEffect.spacing = 8
    container.effect = containerEffect

    let inputGlass = UIGlassEffect(style: .regular)
    inputGlass.isInteractive = true
    inputSurface.effect = inputGlass
    inputSurface.cornerConfiguration = .capsule(maximumRadius: 26)

    let attachGlass = UIGlassEffect(style: .regular)
    attachGlass.isInteractive = true
    attachSurface.effect = attachGlass
    attachSurface.cornerConfiguration = .capsule()
    attachBottom = attachSurface.bottomAnchor.constraint(equalTo: inputSurface.bottomAnchor, constant: -2)
    separateAttachLeading = attachSurface.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16)
    focusedAttachLeading = attachSurface.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22)
    separateInputLeading = inputSurface.leadingAnchor.constraint(equalTo: attachSurface.trailingAnchor, constant: 8)
    focusedInputLeading = inputSurface.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16)
  }

  func activate() {
    NSLayoutConstraint.activate([separateAttachLeading, separateInputLeading, attachBottom])
    placeButton()
  }

  private func placeButton() {
    NSLayoutConstraint.deactivate(buttonConstraints)
    let host = isFocused ? inputSurface.contentView : attachSurface.contentView
    host.addSubview(attachButton)
    buttonConstraints = [
      attachButton.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: isFocused ? 6 : 0),
      attachButton.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: isFocused ? -2 : 0),
      attachButton.widthAnchor.constraint(equalToConstant: 44),
      attachButton.heightAnchor.constraint(equalToConstant: 44),
    ]
    NSLayoutConstraint.activate(buttonConstraints)
  }

  func update(isFocused: Bool) {
    guard self.isFocused != isFocused else { return }
    self.isFocused = isFocused
    // Only the glass travels. Rehost invisible content, then reveal it at rest.
    glyph.layer.removeAllAnimations()
    glyph.alpha = 0
    glyph.transform = .identity
    attachSurface.isUserInteractionEnabled = !isFocused
    placeButton()
    NSLayoutConstraint.deactivate([separateAttachLeading, separateInputLeading, focusedAttachLeading, focusedInputLeading])
    if isFocused {
      NSLayoutConstraint.activate([focusedAttachLeading, focusedInputLeading])
    } else {
      NSLayoutConstraint.activate([separateAttachLeading, separateInputLeading])
    }
  }

  func completeTransition() {
    glyph.image = isFocused ? focusedImage : restingImage
    glyph.accessibilityIdentifier = isFocused ? "session-attach-focused-glyph" : "session-attach-glyph"
    attachButton.layoutIfNeeded()
    guard !UIAccessibility.isReduceMotionEnabled, glyph.window != nil else {
      glyph.alpha = 1
      glyph.transform = .identity
      return
    }
    glyph.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
    UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
      self.glyph.alpha = 1
      self.glyph.transform = .identity
    }
  }
}
