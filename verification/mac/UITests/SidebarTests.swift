import XCTest

final class SidebarTests: LodyMacUITestCase {
  func testPinnedSessionsLeadProjectsOrderedByRecency() {
    for appearance in ["light", "dark"] {
      open("sidebar", appearance)
      let outline = scene.outlines["sidebar-sessions"]
      XCTAssertTrue(outline.waitForExistence(timeout: 5))
      let titles = outline.cells.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
      XCTAssertEqual(titles, [
        "Q4 roadmap",
        "Build the AppKit sidebar", "Review transcript projection", "Native window tabs",
        "Landing page copy", "Deploy preview",
      ], "pinned first, then projects by recency, archived sessions left out")
      XCTAssertEqual(scene.buttons["sidebar-approvals"].title, "Needs Approval · 1", "the approval shortcut counts the waiting session")
      XCTAssertEqual(value(scene.staticTexts["sidebar-machines"]), "Machines online: 2", "the footer reports machine presence")
      attach("sidebar-\(appearance)", scene)
    }
    let approvals = scene.buttons["sidebar-approvals"]
    XCTAssertTrue(approvals.isEnabled, "the shortcut is live while a session waits")
    approvals.click()
    eventually("the shortcut opens the waiting session") { scene.title.hasPrefix("Catalog · Landing page copy") }
    attach("sidebar-approval-dark", scene)
    scene.outlines["sidebar-sessions"].cells["Native window tabs"].click()
    eventually("selecting a session opens it") { scene.title.hasPrefix("Catalog · Native window tabs") }
  }
}
