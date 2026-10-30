import XCTest

final class AccentTests: LodyMacUITestCase {
  private func swatch(_ accent: String) -> XCUIElement { app.buttons["settings-appearance-accent-\(accent)"] }

  func testAccentSwatchesRetintTheApp() {
    for appearance in ["light", "dark"] {
      open("accent", appearance)
      XCTAssertTrue(swatch("system").waitForExistence(timeout: 5))
      XCTAssertTrue(swatch("system").isSelected, "the scene starts on the system accent")
      for accent in ["purple", "orange"] {
        swatch(accent).click()
        eventually("the \(accent) swatch applies") { swatch(accent).isSelected && !swatch("system").isSelected }
        attach("accent-\(accent)-\(appearance)")
      }
    }
    swatch("system").click()
    eventually("the system accent comes back for later cases") { swatch("system").isSelected }
  }
}
