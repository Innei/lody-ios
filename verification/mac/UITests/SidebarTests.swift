import XCTest

final class SidebarTests: LodyMacUITestCase {
  private let sessionTitles = ["Build the AppKit sidebar", "Review transcript projection", "Native window tabs", "Q4 roadmap", "Landing page copy", "Deploy preview", "Archived spike"]

  private func titles(_ outline: XCUIElement) -> [String] {
    outline.cells.allElementsBoundByIndex.map(\.label).filter { sessionTitles.contains($0) }
  }

  func testMachineProjectsAndCompactSessionsInBothAppearances() {
    for appearance in ["light", "dark"] {
      open("sidebar", appearance)
      let outline = scene.outlines["sidebar-sessions"]
      XCTAssertTrue(outline.waitForExistence(timeout: 5))
      XCTAssertEqual(titles(outline), Array(sessionTitles.prefix(6)))
      XCTAssertTrue(scene.buttons["sidebar-new-session"].exists)
      XCTAssertTrue(scene.buttons["sidebar-search-action"].exists)
      XCTAssertTrue(scene.menuButtons["sidebar-workspace"].exists)
      XCTAssertTrue(scene.buttons["sidebar-archive"].exists)
      scene.textViews["composer-input"].click()
      attach("sidebar-\(appearance)", scene)
    }
    scene.outlines["sidebar-sessions"].cells["Landing page copy"].click()
    eventually("selecting attention opens the waiting session") { scene.title.hasPrefix("Catalog · Landing page copy") }
    attach("sidebar-approval-dark", scene)
  }

  func testSearchProjectDisclosureArchiveAndNativeDestinations() {
    open("sidebar", "light")
    let outline = scene.outlines["sidebar-sessions"]
    app.typeKey("f", modifierFlags: .command)
    let search = scene.searchFields["sidebar-search"]
    XCTAssertTrue(search.waitForExistence(timeout: 3))
    search.typeText("sidebar")
    eventually("search filters without changing the conversation") { titles(outline) == ["Build the AppKit sidebar"] }
    attach("sidebar-search-focus-light", scene)
    search.typeKey("a", modifierFlags: .command)
    search.typeText("no matching task")
    eventually("empty search explains what happened") { value(scene.staticTexts["sidebar-empty"]) == "No matching sessions" }
    attach("sidebar-search-empty-light", scene)
    search.typeKey("a", modifierFlags: .command)
    search.typeText(XCUIKeyboardKey.delete.rawValue)
    eventually("clearing search restores projects") { titles(outline).count == 6 }
    let filter = scene.menuButtons["sidebar-filter"]
    filter.click()
    XCTAssertTrue(app.menuItems["lody-web"].waitForExistence(timeout: 3))
    attach("sidebar-project-menu-light", scene)
    app.menuItems["lody-web"].click()
    eventually("project scope shows only its sessions") { titles(outline) == ["Landing page copy", "Deploy preview"] }
    attach("sidebar-project-filtered-light", scene)
    choose("All Projects", in: filter)
    eventually("all projects restores sessions") { titles(outline).count == 6 }
    outline.cells["Landing page copy"].rightClick()
    XCTAssertTrue(app.menuItems["Open in New Tab"].waitForExistence(timeout: 3))
    attach("sidebar-context-menu-light", scene)
    app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
    outline.disclosureTriangles.firstMatch.click()
    eventually("collapsing a project hides its sessions") { !titles(outline).contains("Build the AppKit sidebar") }
    attach("sidebar-project-collapsed-light", scene)
    outline.disclosureTriangles.firstMatch.click()
    eventually("expanding restores its sessions") { titles(outline).contains("Build the AppKit sidebar") }
    scene.buttons["sidebar-archive"].click()
    eventually("archive contains only archived sessions") { titles(outline) == ["Archived spike"] }
    attach("sidebar-archive-light", scene)
    scene.buttons["sidebar-archive"].click()
    eventually("leaving archive restores projects") { titles(outline).count == 6 }
    scene.buttons["sidebar-new-session"].click()
    eventually("new chat opens the native draft") { scene.title == "Catalog · New Session" }
    attach("sidebar-new-session-light", scene)
    scene.buttons["sidebar-manage-projects"].click()
    let projects = app.windows.matching(NSPredicate(format: "title == 'Projects'")).firstMatch
    XCTAssertTrue(projects.waitForExistence(timeout: 5))
    XCTAssertTrue(projects.staticTexts["lody-ios"].waitForExistence(timeout: 5))
    attach("sidebar-projects-destination-light", projects)
  }
}
