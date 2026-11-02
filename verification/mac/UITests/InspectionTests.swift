import XCTest

final class InspectionTests: LodyMacUITestCase {
  func testDiffFileTreePreviewAndCompactRestore() {
    open("inspection", "light")
    for appearance in ["light", "dark"] {
      let first = "macOS/Views/Composer/MacComposerView.swift"
      open("inspection-wide", appearance)
      XCTAssertTrue(scene.buttons.matching(identifier: "inspection-context-" + first).firstMatch.waitForExistence(timeout: 5))
      eventually("wide fixture uses its requested window size") { abs(self.scene.frame.width - 1440) < 2 && abs(self.scene.frame.height - 900) < 2 }
      XCTAssertTrue(scene.buttons["sidebar-search"].exists)
      scene.buttons["window-sidebar-toggle"].click()
      eventually("the grouped sidebar control hides the sidebar") { !self.scene.buttons["sidebar-search"].isHittable }
      scene.buttons["window-sidebar-toggle"].click()
      eventually("the grouped sidebar control restores the sidebar") { self.scene.buttons["sidebar-search"].isHittable }
      attach("inspection-wide-\(appearance)", scene)
      open("inspection", appearance)
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
      attach("inspection-tree-\(appearance)", app)
      filter.click(); filter.typeText("changes-reference.png")
      app.outlineRows.containing(.staticText, identifier: "changes-reference.png").firstMatch.click()
      XCTAssertTrue(scene.images["inspection-image"].waitForExistence(timeout: 5))
      attach("inspection-image-fit-\(appearance)", scene)
      choose("200%", in: scene.popUpButtons["inspection-image-zoom"])
      attach("inspection-image-\(appearance)", scene)
      scene.descendants(matching: .any).matching(identifier: "inspection-tab-" + first).firstMatch.click()
      XCTAssertTrue(text.waitForExistence(timeout: 3))
      attach("inspection-tabs-\(appearance)", scene)
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
      scene.buttons["inspection-preview-" + first].click()
      let smallTab = scene.buttons["inspection-tab-" + first]
      XCTAssertTrue(smallTab.waitForExistence(timeout: 3))
      smallTab.doubleClick()
      scene.buttons["inspection-new-tab"].click()
      XCTAssertTrue(filter.waitForExistence(timeout: 3))
      filter.click(); filter.typeText("changes-reference.png")
      app.outlineRows.containing(.staticText, identifier: "changes-reference.png").firstMatch.click()
      let imageClose = scene.buttons["inspection-close-changes-reference.png"]
      XCTAssertTrue(imageClose.waitForExistence(timeout: 3))
      XCTAssertTrue(imageClose.isHittable, "The selected file's close button must remain reachable at 760 pt")
      attach("inspection-small-image-tabs-\(appearance)", scene)
      imageClose.click()
      XCTAssertTrue(scene.textViews["inspection-text"].waitForExistence(timeout: 3))
      attach("inspection-small-code-tabs-\(appearance)", scene)
    }
  }
}
