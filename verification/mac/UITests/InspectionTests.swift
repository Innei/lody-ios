import XCTest

final class InspectionTests: LodyMacUITestCase {
  func testDiffFileTreePreviewAndCompactRestore() {
    for appearance in ["light", "dark"] {
      open("inspection", appearance)
      let first = "macOS/Views/MacComposerView.swift"
      let preview = scene.buttons["inspection-preview-" + first]
      XCTAssertTrue(preview.waitForExistence(timeout: 5))
      attach("inspection-diff-\(appearance)", scene)
      preview.click()
      let text = scene.textViews["inspection-text"]
      XCTAssertTrue(text.waitForExistence(timeout: 5))
      XCTAssertTrue(value(text).contains("MacComposerView"))
      text.click()
      text.typeKey("f", modifierFlags: .command)
      attach("inspection-find-\(appearance)", scene)
      text.typeKey(.escape, modifierFlags: [])
      let tab = scene.descendants(matching: .any).matching(identifier: "inspection-tab-" + first).firstMatch
      tab.doubleClick()
      scene.buttons["inspection-files"].click()
      let filter = app.searchFields["inspection-file-filter"]
      XCTAssertTrue(filter.waitForExistence(timeout: 3))
      XCTAssertGreaterThan(filter.frame.width, 250)
      filter.click(); filter.typeText("preview.png")
      app.outlineRows.containing(.staticText, identifier: "preview.png").firstMatch.click()
      XCTAssertTrue(scene.images["inspection-image"].waitForExistence(timeout: 5))
      choose("200%", in: scene.popUpButtons["inspection-image-zoom"])
      attach("inspection-image-\(appearance)", scene)
      scene.descendants(matching: .any).matching(identifier: "inspection-tab-" + first).firstMatch.click()
      XCTAssertTrue(text.waitForExistence(timeout: 3))
      scene.buttons["inspection-changes-tab"].click()
      choose("This reply", in: scene.popUpButtons["inspection-range"])
      attach("inspection-turn-\(appearance)", scene)
      scene.buttons["inspection-expand"].click()
      attach("inspection-expanded-\(appearance)", scene)
      scene.buttons["inspection-expand"].click()
      scene.buttons["inspection-close"].click()
      open("inspection-small", appearance)
      XCTAssertTrue(scene.buttons["inspection-changes-tab"].waitForExistence(timeout: 5))
      attach("inspection-small-\(appearance)", scene)
    }
  }
}
