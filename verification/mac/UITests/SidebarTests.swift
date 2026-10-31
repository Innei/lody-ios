import XCTest

final class SidebarTests: LodyMacUITestCase {
  private let sessionTitles = ["Build the AppKit sidebar", "Review transcript projection", "Native window tabs", "Q4 roadmap", "Landing page copy", "Deploy preview", "Archived spike"]

  private func titles(_ outline: XCUIElement) -> [String] {
    outline.cells.allElementsBoundByIndex.map(\.label).filter { sessionTitles.contains($0) }
  }

  func testNativeChromeStudiesInBothAppearances() {
    for appearance in ["light", "dark"] {
      for kind in ["footer", "reply", "new"] {
        for variant in ["a", "b", "c"] {
          let name = "chrome-\(kind)-\(variant)"
          open(name, appearance)
          XCTAssertTrue(scene.outlines["sidebar-sessions"].exists)
          if kind != "footer" {
            let input = scene.textViews["chrome-study-input"]
            XCTAssertTrue(input.exists)
            XCTAssertEqual(value(input), "Keep the AppKit controls and align the sidebar rows.")
            XCTAssertGreaterThan(input.frame.width, 500, "compare variants at the same available reading width")
          }
          attach("\(name)-\(appearance)", scene)
        }
      }
    }
  }

  func testSidebarToggleAnimationKeepsWindowFrameAndWideChatCentered() {
    for appearance in ["light", "dark"] {
      open("sidebar", appearance)
      let outline = scene.outlines["sidebar-sessions"]
      let toggle = scene.toolbars.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sidebar' OR identifier CONTAINS[c] 'sidebar'")).firstMatch
      XCTAssertTrue(toggle.waitForExistence(timeout: 5))
      XCTAssertLessThan(abs(outline.frame.maxX - toggle.frame.maxX), 40, "the toggle sits at the sidebar's trailing edge")
      let before = scene.frame
      toggle.click()
      eventually("sidebar collapses") { !scene.buttons["sidebar-new-session"].isHittable }
      assertFrame(before, scene.frame)
      attach("sidebar-hidden-\(appearance)", scene)
      XCTAssertTrue(toggle.isHittable, "the native toggle remains available while the sidebar is hidden")
      toggle.click()
      eventually("sidebar expands") { scene.buttons["sidebar-new-session"].isHittable }
      assertFrame(before, scene.frame)
      attach("sidebar-restored-\(appearance)", scene)

      // Move into the guest's usable screen before resizing the actual native window.
      let titlebar = scene.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.025))
      titlebar.click(forDuration: 0.25, thenDragTo: titlebar.withOffset(CGVector(dx: 40 - scene.frame.minX, dy: 0)))
      eventually("the native window moves into the usable screen") { scene.frame.minX < 100 }
      resize(to: 1460)
      eventually("the window can grow beyond the reading column") { scene.frame.width > 1400 }
      let prose = scene.staticTexts["transcript-prose"].firstMatch
      XCTAssertTrue(prose.exists)
      XCTAssertLessThanOrEqual(prose.frame.width, 780)
      XCTAssertEqual(prose.frame.midX, (outline.frame.maxX + scene.frame.maxX) / 2, accuracy: 10)
      attach("sidebar-wide-\(appearance)", scene)
      let wide = scene.frame
      toggle.click()
      eventually("wide sidebar collapses") { !scene.buttons["sidebar-new-session"].isHittable }
      assertFrame(wide, scene.frame)
      XCTAssertEqual(prose.frame.midX, scene.frame.midX, accuracy: 10)
      attach("sidebar-wide-hidden-\(appearance)", scene)
      toggle.click()
      eventually("wide sidebar expands") { scene.buttons["sidebar-new-session"].isHittable }
      assertFrame(wide, scene.frame)
      resize(to: 800)
      eventually("the window can shrink with both panes visible") { scene.frame.width < 850 }
      attach("sidebar-narrow-\(appearance)", scene)
    }
  }

  private func resize(to width: CGFloat) {
    let edge = scene.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -1, dy: 0))
    edge.click(forDuration: 0.25, thenDragTo: edge.withOffset(CGVector(dx: width - scene.frame.width, dy: 0)))
  }

  private func assertFrame(_ before: CGRect, _ after: CGRect) {
    XCTAssertEqual(before.minX, after.minX, accuracy: 1)
    XCTAssertEqual(before.minY, after.minY, accuracy: 1)
    XCTAssertEqual(before.width, after.width, accuracy: 1)
    XCTAssertEqual(before.height, after.height, accuracy: 1)
  }

  func testMachineProjectsAndCompactSessionsInBothAppearances() {
    for appearance in ["light", "dark"] {
      open("sidebar", appearance)
      let outline = scene.outlines["sidebar-sessions"]
      XCTAssertTrue(outline.waitForExistence(timeout: 5))
      XCTAssertEqual(titles(outline), Array(sessionTitles.prefix(6)))
      XCTAssertTrue(scene.buttons["sidebar-new-session"].exists)
      XCTAssertTrue(scene.searchFields["sidebar-search"].exists)
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
    search.typeText("Landing")
    eventually("search filters the project list") { titles(outline) == ["Landing page copy"] }
    scene.buttons["sidebar-search-clear"].click()
    eventually("the clear button restores sessions") { titles(outline).count == 6 }
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
    outline.buttons["Collapse lody-ios"].click()
    eventually("collapsing a project hides its sessions") { !titles(outline).contains("Build the AppKit sidebar") }
    attach("sidebar-project-collapsed-light", scene)
    outline.buttons["Expand lody-ios"].click()
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
