import UIKit

@MainActor
enum LodyNativePages {
  private static let factories: [String: () -> UIViewController] = [
    "appearance-settings": { AppearanceController() },
    "app-icon": { AppIconController() },
  ]

  static func make(_ id: String) -> UIViewController? { factories[id]?() }
}
