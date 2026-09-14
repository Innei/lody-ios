import UIKit

final class ChatComposerLiquidGlassSurfaceLayout: ChatComposerSurfaceLayout {
  private let inputSurface: UIVisualEffectView
  private let attachSurface: UIVisualEffectView
  private let attachButton: UIButton
  private let glyphHost: UIView
  private let glyph = UIImageView()
  private let restingImage: UIImage?
  private let focusedImage = UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular))
  private let glyphWidth: NSLayoutConstraint
  private let glyphHeight: NSLayoutConstraint
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
    let restingSize = restingImage?.size ?? .zero
    let glyphHost = UIView(frame: CGRect(origin: .zero, size: restingSize))
    self.glyphHost = glyphHost
    glyphHost.translatesAutoresizingMaskIntoConstraints = false
    glyphHost.isUserInteractionEnabled = false
    glyphHost.isAccessibilityElement = false
    glyph.image = restingImage
    glyph.frame = glyphHost.bounds
    glyph.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    glyph.contentMode = .scaleAspectFit
    glyph.tintColor = attachButton.tintColor
    glyph.isUserInteractionEnabled = false
    glyph.isAccessibilityElement = false
    glyph.accessibilityIdentifier = "session-attach-glyph"
    glyphHost.addSubview(glyph)
    attachButton.addSubview(glyphHost)
    glyphWidth = glyphHost.widthAnchor.constraint(equalToConstant: restingSize.width)
    glyphHeight = glyphHost.heightAnchor.constraint(equalToConstant: restingSize.height)
    glyphHost.setContentHuggingPriority(.required, for: .horizontal)
    glyphHost.setContentHuggingPriority(.required, for: .vertical)
    glyphHost.setContentCompressionResistancePriority(.required, for: .horizontal)
    glyphHost.setContentCompressionResistancePriority(.required, for: .vertical)
    NSLayoutConstraint.activate([
      glyphHost.centerXAnchor.constraint(equalTo: attachButton.centerXAnchor),
      glyphHost.centerYAnchor.constraint(equalTo: attachButton.centerYAnchor),
      glyphWidth,
      glyphHeight,
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
    let frame = attachButton.convert(attachButton.bounds, to: host)
    host.addSubview(attachButton)
    if !attachButton.bounds.isEmpty { attachButton.frame = frame }
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
    attachSurface.isUserInteractionEnabled = !isFocused
    // Keep the plus on attach glass until the merged frames already coincide.
    if !isFocused { placeButton() }
    NSLayoutConstraint.deactivate([separateAttachLeading, separateInputLeading, focusedAttachLeading, focusedInputLeading])
    if isFocused {
      NSLayoutConstraint.activate([focusedAttachLeading, focusedInputLeading])
    } else {
      NSLayoutConstraint.activate([separateAttachLeading, separateInputLeading])
    }
  }

  func completeTransition() {
    let image = isFocused ? focusedImage : restingImage
    glyph.image = image
    glyph.accessibilityIdentifier = isFocused ? "session-attach-focused-glyph" : "session-attach-glyph"
    let size = image?.size ?? .zero
    glyphWidth.constant = size.width
    glyphHeight.constant = size.height
    UIView.performWithoutAnimation {
      if isFocused { placeButton() }
      attachButton.layoutIfNeeded()
    }
  }
}
