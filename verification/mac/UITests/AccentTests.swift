import AppKit
import XCTest

final class AccentTests: LodyMacUITestCase {
  private let hues = ["purple": 260.0...330.0, "orange": 15.0...50.0]

  private func swatch(_ accent: String) -> XCUIElement { app.buttons["settings-appearance-accent-\(accent)"] }

  private func hue(of element: XCUIElement) -> Double {
    guard let tiff = element.screenshot().image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return -1 }
    var best = (score: -1.0, hue: -1.0)
    for x in 0..<bitmap.pixelsWide {
      for y in 0..<bitmap.pixelsHigh {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
        let score = Double(color.saturationComponent * color.brightnessComponent)
        if score > best.score { best = (score, Double(color.hueComponent) * 360) }
      }
    }
    return best.hue
  }

  func testAccentSwatchesRetintTheApp() {
    for appearance in ["light", "dark"] {
      open("accent", appearance)
      XCTAssertTrue(swatch("system").waitForExistence(timeout: 5))
      XCTAssertTrue(swatch("system").isSelected, "the scene starts on the system accent")
      for accent in ["purple", "orange"] {
        swatch(accent).click()
        eventually("the \(accent) swatch applies") { swatch(accent).isSelected && !swatch("system").isSelected }
        let workspace = app.windows.matching(NSPredicate(format: "title BEGINSWITH 'Catalog · Build'")).firstMatch
        let dot = workspace.outlines["sidebar-sessions"].cells["Build the AppKit sidebar"].images.firstMatch
        var measured = -1.0
        eventually("the workspace's running dot retints \(accent) (hue \(measured))") {
          measured = hue(of: dot)
          return hues[accent]?.contains(measured) == true
        }
        attach("accent-\(accent)-\(appearance)")
      }
    }
    swatch("system").click()
    eventually("the system accent comes back for later cases") { swatch("system").isSelected }
  }
}
