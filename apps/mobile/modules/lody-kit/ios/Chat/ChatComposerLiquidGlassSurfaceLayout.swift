import UIKit

final class ChatComposerLiquidGlassSurfaceLayout: ChatComposerSurfaceLayout {
  private let container: UIVisualEffectView
  private let inputSurface: UIVisualEffectView
  private let attachSurface: UIVisualEffectView
  private let attachButton: UIButton
  private let attachGlyph: UIImageView
  private let focusedGlyph: UIImageView
  private let focusedGlyphSize: CGSize
  private let restingGlyphSize: CGSize
  private let glyphWidth: NSLayoutConstraint
  private let glyphHeight: NSLayoutConstraint
  private let separateAttachLeading: NSLayoutConstraint
  private let focusedAttachLeading: NSLayoutConstraint
  private let separateInputLeading: NSLayoutConstraint
  private let focusedInputLeading: NSLayoutConstraint
  private let attachBottom: NSLayoutConstraint
  private let attachGlass: UIGlassEffect
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
    let focusedGlyph = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)))
    self.focusedGlyph = focusedGlyph
    focusedGlyphSize = focusedGlyph.image!.size
    restingGlyphSize = attachGlyph.image?.size ?? attachGlyph.intrinsicContentSize
    attachButton.setImage(nil, for: .normal)
    attachButton.configuration?.image = nil
    let glyphHost = UIView(frame: CGRect(origin: .zero, size: restingGlyphSize))
    glyphHost.translatesAutoresizingMaskIntoConstraints = false
    glyphHost.isUserInteractionEnabled = false
    for glyph in [attachGlyph, focusedGlyph] {
      glyphHost.addSubview(glyph)
      glyph.frame = glyphHost.bounds
      glyph.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      glyph.contentMode = .scaleAspectFit
      glyph.tintColor = attachButton.tintColor
      glyph.isUserInteractionEnabled = false
      glyph.isAccessibilityElement = false
    }
    focusedGlyph.alpha = 0
    focusedGlyph.accessibilityIdentifier = "session-attach-focused-glyph"
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
    self.attachGlass = attachGlass
    attachGlass.isInteractive = true
    attachSurface.effect = attachGlass
    attachSurface.cornerConfiguration = .capsule()
    attachBottom = attachSurface.bottomAnchor.constraint(equalTo: inputSurface.bottomAnchor, constant: -2)

    separateAttachLeading = attachSurface.leadingAnchor.constraint(
      equalTo: container.leadingAnchor,
      constant: 16
    )
    focusedAttachLeading = attachSurface.leadingAnchor.constraint(
      equalTo: container.leadingAnchor,
      constant: 22
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
    NSLayoutConstraint.activate([separateAttachLeading, separateInputLeading, attachBottom])
  }

  func update(isFocused: Bool) {
    guard self.isFocused != isFocused else { return }
    self.isFocused = isFocused
    let parent = container.contentView
    let frame = attachSurface.convert(attachSurface.bounds, to: parent)
    NSLayoutConstraint.deactivate([separateAttachLeading, separateInputLeading, focusedAttachLeading, focusedInputLeading, attachBottom])
    // Keep both surfaces in the glass container until their native merge finishes.
    attachGlass.isInteractive = !isFocused
    attachSurface.effect = attachGlass
    parent.addSubview(attachSurface)
    attachSurface.frame = frame
    if isFocused {
      NSLayoutConstraint.activate([focusedAttachLeading, focusedInputLeading, attachBottom])
    } else {
      NSLayoutConstraint.activate([separateAttachLeading, separateInputLeading, attachBottom])
    }
    let glyphSize = isFocused ? focusedGlyphSize : restingGlyphSize
    glyphWidth.constant = glyphSize.width
    glyphHeight.constant = glyphSize.height
    let updateGlyph = {
      self.attachGlyph.alpha = isFocused ? 0 : 1
      self.focusedGlyph.alpha = isFocused ? 1 : 0
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

  func completeTransition() {
    guard isFocused, attachSurface.superview !== inputSurface.contentView else { return }
    // Once merged, hand off to the input's press transform without changing geometry.
    UIView.performWithoutAnimation {
      let frame = attachSurface.convert(attachSurface.bounds, to: inputSurface.contentView)
      NSLayoutConstraint.deactivate([focusedAttachLeading, attachBottom])
      inputSurface.contentView.addSubview(attachSurface)
      attachSurface.frame = frame
      attachSurface.effect = nil
      NSLayoutConstraint.activate([focusedAttachLeading, attachBottom])
      container.layoutIfNeeded()
    }
  }
}
