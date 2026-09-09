import UIKit

@available(iOS 26.0, *)
final class ChatComposerLiquidGlassSurfaceLayout: ChatComposerSurfaceLayout {
  private let container: UIVisualEffectView
  private let inputSurface: UIVisualEffectView
  private let attachSurface: UIVisualEffectView
  private let attachButton: UIButton
  private let attachGlyph: UIImageView
  private let restingGlyphSize: CGSize
  private let glyphWidth: NSLayoutConstraint
  private let glyphHeight: NSLayoutConstraint
  private let separateAttachLeading: NSLayoutConstraint
  private let focusedAttachLeading: NSLayoutConstraint
  private let separateInputLeading: NSLayoutConstraint
  private let focusedInputLeading: NSLayoutConstraint
  private var isFocused = false

  init(
    container: UIVisualEffectView,
    inputSurface: UIVisualEffectView,
    attachSurface: UIVisualEffectView,
    attachButton: UIButton
  ) {
    self.container = container
    self.inputSurface = inputSurface
    self.attachSurface = attachSurface
    self.attachButton = attachButton
    let attachGlyph = UIImageView(image: attachButton.image(for: .normal))
    self.attachGlyph = attachGlyph
    restingGlyphSize = attachGlyph.image?.size ?? attachGlyph.intrinsicContentSize
    attachButton.setImage(nil, for: .normal)
    let glyphHost = UIView(frame: CGRect(origin: .zero, size: restingGlyphSize))
    glyphHost.translatesAutoresizingMaskIntoConstraints = false
    glyphHost.isUserInteractionEnabled = false
    glyphHost.addSubview(attachGlyph)
    attachGlyph.frame = glyphHost.bounds
    attachGlyph.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    attachGlyph.contentMode = .scaleAspectFit
    attachGlyph.tintColor = attachButton.tintColor
    attachGlyph.isUserInteractionEnabled = false
    attachGlyph.isAccessibilityElement = false
    attachGlyph.accessibilityIdentifier = "session-attach-glyph"
    attachButton.addSubview(glyphHost)
    glyphWidth = glyphHost.widthAnchor.constraint(equalToConstant: restingGlyphSize.width)
    glyphHeight = glyphHost.heightAnchor.constraint(equalToConstant: restingGlyphSize.height)
    NSLayoutConstraint.activate([
      glyphHost.centerXAnchor.constraint(equalTo: attachButton.centerXAnchor),
      glyphHost.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor),
      glyphWidth,
      glyphHeight,
    ])

    let containerEffect = UIGlassContainerEffect()
    containerEffect.spacing = 4
    container.effect = containerEffect

    let inputGlass = UIGlassEffect(style: .regular)
    inputGlass.isInteractive = true
    inputSurface.effect = inputGlass
    inputSurface.cornerConfiguration = .capsule(maximumRadius: 26)

    let attachGlass = UIGlassEffect(style: .regular)
    attachGlass.isInteractive = true
    attachSurface.effect = attachGlass
    attachSurface.cornerConfiguration = .capsule()

    separateAttachLeading = attachSurface.leadingAnchor.constraint(
      equalTo: container.leadingAnchor,
      constant: 16
    )
    focusedAttachLeading = attachSurface.leadingAnchor.constraint(
      equalTo: container.leadingAnchor,
      constant: 18
    )
    separateInputLeading = inputSurface.leadingAnchor.constraint(
      equalTo: attachSurface.trailingAnchor,
      constant: 8
    )
    focusedInputLeading = inputSurface.leadingAnchor.constraint(
      equalTo: container.leadingAnchor,
      constant: 16
    )
  }

  func activate() {
    NSLayoutConstraint.activate([separateAttachLeading, separateInputLeading])
  }

  func update(isFocused: Bool) {
    guard self.isFocused != isFocused else { return }
    self.isFocused = isFocused
    if isFocused {
      NSLayoutConstraint.deactivate([separateAttachLeading, separateInputLeading])
      NSLayoutConstraint.activate([focusedAttachLeading, focusedInputLeading])
      container.contentView.bringSubviewToFront(attachSurface)
    } else {
      NSLayoutConstraint.deactivate([focusedAttachLeading, focusedInputLeading])
      NSLayoutConstraint.activate([separateAttachLeading, separateInputLeading])
    }
    let glyphScale: CGFloat = isFocused ? 11 / 17 : 1
    glyphWidth.constant = restingGlyphSize.width * glyphScale
    glyphHeight.constant = restingGlyphSize.height * glyphScale
    let updateGlyph = {
      self.attachButton.layoutIfNeeded()
    }
    if UIAccessibility.isReduceMotionEnabled || attachGlyph.window == nil {
      updateGlyph()
    } else {
      UIView.animate(
        withDuration: 0.24,
        delay: 0,
        options: [.beginFromCurrentState, .curveEaseOut],
        animations: updateGlyph
      )
    }
  }
}
