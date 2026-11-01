import XCTest

final class TranscriptTests: LodyMacUITestCase {
  private var prose: XCUIElementQuery { scene.staticTexts.matching(identifier: "transcript-prose") }

  func testPermissionCardAnswersAndTheReplyRenders() {
    for appearance in ["light", "dark"] {
      open("transcript", appearance)
      XCTAssertTrue(scene.staticTexts["Read MainWindowController.swift"].waitForExistence(timeout: 5))
      XCTAssertTrue(scene.staticTexts["Add a sidebar like the Codex desktop app: pinned sessions, then projects."].exists, "one user turn")
      for line in ["Search for NSSplitViewController", "Waiting for approval · Edit SidebarViewController.swift"] {
        XCTAssertTrue(scene.staticTexts[line].exists, "tool calls render as quiet activity lines: \(line)")
      }
      XCTAssertEqual(prose.count, 1)
      XCTAssertTrue(value(prose.element(boundBy: 0)).hasPrefix("I'll add an NSOutlineView source list:"), "assistant prose renders as Markdown")
      XCTAssertTrue(scene.staticTexts["Edit SidebarViewController.swift"].exists)
      XCTAssertTrue(scene.buttons["permission-option-0"].isEnabled, "the permission card offers Allow")
      XCTAssertFalse(scene.buttons["permission-continue"].exists)
      attach("transcript-\(appearance)", scene)
    }
    scene.buttons["permission-option-0"].click()
    eventually("one click resolves the permission card") { !scene.buttons["permission-option-0"].exists }
    eventually("the reply after approval renders") { prose.count == 2 }
    XCTAssertTrue(value(prose.element(boundBy: 1)).hasPrefix("Approved. The sidebar now groups sessions by project"))
    attach("transcript-answered-dark", scene)
  }
}
