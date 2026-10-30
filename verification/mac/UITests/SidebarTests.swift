import XCTest

final class SidebarTests: LodyMacUITestCase {
  private func titles(_ outline: XCUIElement) -> [String] {
    outline.cells.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty && $0 != "Working" && $0 != "Settled" }
  }

  func testPinnedAndActiveSessionsLeadTheWorkingAndSettledShelves() {
    for appearance in ["light", "dark"] {
      open("sidebar", appearance)
      let outline = scene.outlines["sidebar-sessions"]
      XCTAssertTrue(outline.waitForExistence(timeout: 5))
      XCTAssertEqual(titles(outline), [
        "Q4 roadmap",
        "Landing page copy", "Review transcript projection", "Native window tabs", "Deploy preview",
        "Build the AppKit sidebar",
      ], "pinned and attention stay above working; settled starts closed")
      XCTAssertTrue(scene.buttons["sidebar-new-session"].exists)
      XCTAssertTrue(scene.searchFields["sidebar-search"].exists)
      XCTAssertTrue(scene.popUpButtons["sidebar-workspace"].exists)
      XCTAssertEqual(scene.buttons["sidebar-machines"].label, "Machines online: 2")
      scene.textViews["composer-input"].click()
      attach("sidebar-\(appearance)", scene)
    }
    scene.outlines["sidebar-sessions"].cells["Landing page copy"].click()
    eventually("selecting attention opens the waiting session") { scene.title.hasPrefix("Catalog · Landing page copy") }
    attach("sidebar-approval-dark", scene)
    scene.outlines["sidebar-sessions"].cells["Native window tabs"].click()
    eventually("selecting a session opens it") { scene.title.hasPrefix("Catalog · Native window tabs") }
  }

  func testSearchProjectMenusAndNewSessionUseTheNativeControls() {
    open("sidebar", "light")
    let outline = scene.outlines["sidebar-sessions"]
    let search = scene.searchFields["sidebar-search"]
    app.typeKey("f", modifierFlags: .command)
    search.typeText("sidebar")
    eventually("search finds the working session without moving the conversation") { titles(outline) == ["Build the AppKit sidebar"] }
    attach("sidebar-search-focus-light", scene)
    search.typeKey("a", modifierFlags: .command)
    search.typeText("no matching task")
    eventually("empty search explains what happened") { value(scene.staticTexts["sidebar-empty"]) == "No matching sessions" }
    attach("sidebar-search-empty-light", scene)
    search.typeKey("a", modifierFlags: .command)
    search.typeText(XCUIKeyboardKey.delete.rawValue)
    eventually("clearing search restores the shelves") { titles(outline).count == 6 }
    let filter = scene.menuButtons["sidebar-filter"]
    filter.click()
    XCTAssertTrue(app.menuItems["lody-web"].waitForExistence(timeout: 3))
    attach("sidebar-project-menu-light", scene)
    app.menuItems["lody-web"].click()
    eventually("project scope shows only that project's sessions") { titles(outline) == ["Landing page copy", "Deploy preview"] }
    attach("sidebar-project-filtered-light", scene)
    choose("All Projects", in: filter)
    eventually("all projects restores every active session") { titles(outline).count == 6 }
    outline.cells["Landing page copy"].rightClick()
    XCTAssertTrue(app.menuItems["Open in New Tab"].waitForExistence(timeout: 3))
    attach("sidebar-context-menu-light", scene)
    app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    let disclosure = outline.disclosureTriangles.element(boundBy: 1)
    XCTAssertTrue(disclosure.exists)
    disclosure.click()
    XCTAssertTrue(outline.cells["Archived spike"].waitForExistence(timeout: 3))
    attach("sidebar-settled-expanded-light", scene)
    scene.buttons["sidebar-new-session"].click()
    eventually("the new-session action opens the native draft") { scene.title == "Catalog · New Session" }
    attach("sidebar-new-session-light", scene)
    scene.buttons["sidebar-manage-projects"].click()
    let projects = app.windows.matching(NSPredicate(format: "title == 'Projects'")).firstMatch
    XCTAssertTrue(projects.waitForExistence(timeout: 5))
    XCTAssertTrue(projects.staticTexts["lody-ios"].waitForExistence(timeout: 5))
    attach("sidebar-projects-destination-light", projects)
  }
}
