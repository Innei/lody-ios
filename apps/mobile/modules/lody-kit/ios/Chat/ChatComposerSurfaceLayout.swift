import UIKit

@MainActor
protocol ChatComposerSurfaceLayout: AnyObject {
  func activate()
  func update(isFocused: Bool)
}

@MainActor
enum ChatComposerSurfaceLayoutFactory {
  static func make(
    container: UIVisualEffectView,
    inputSurface: UIVisualEffectView,
    attachSurface: UIVisualEffectView,
    attachButton: UIButton
  ) -> any ChatComposerSurfaceLayout {
    if #available(iOS 26.0, *) {
      return ChatComposerLiquidGlassSurfaceLayout(
        container: container,
        inputSurface: inputSurface,
        attachSurface: attachSurface,
        attachButton: attachButton
      )
    }
    return ChatComposerLegacySurfaceLayout(
      container: container,
      inputSurface: inputSurface,
      attachSurface: attachSurface
    )
  }
}
