import UIKit

final class ChatComposerLegacySurfaceLayout: ChatComposerSurfaceLayout {
  private let attachLeading: NSLayoutConstraint
  private let inputLeading: NSLayoutConstraint
  private let attachBottom: NSLayoutConstraint

  init(
    container: UIVisualEffectView,
    inputSurface: UIVisualEffectView,
    attachSurface: UIVisualEffectView
  ) {
    inputSurface.layer.cornerRadius = 24
    inputSurface.layer.cornerCurve = .continuous
    inputSurface.clipsToBounds = true
    inputSurface.backgroundColor = .secondarySystemBackground
    attachSurface.layer.cornerRadius = 22
    attachSurface.layer.cornerCurve = .continuous
    attachSurface.clipsToBounds = true
    attachSurface.backgroundColor = .secondarySystemBackground
    attachBottom = attachSurface.bottomAnchor.constraint(equalTo: inputSurface.bottomAnchor, constant: -2)
    attachLeading = attachSurface.leadingAnchor.constraint(
      equalTo: container.leadingAnchor,
      constant: 16
    )
    inputLeading = inputSurface.leadingAnchor.constraint(
      equalTo: attachSurface.trailingAnchor,
      constant: 8
    )
  }

  func activate() {
    NSLayoutConstraint.activate([attachLeading, inputLeading, attachBottom])
  }

  func update(isFocused: Bool) {}
}
