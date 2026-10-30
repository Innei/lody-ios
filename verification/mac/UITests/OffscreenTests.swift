import AppKit
import XCTest

final class OffscreenTests: LodyMacUITestCase {
  func testInProcessModeKeepsEveryWindowOffTheDisplays() {
    let edge = NSScreen.screens.map(\.frame.maxX).max() ?? 0
    if app.state != .notRunning { app.terminate() }
    for (index, name) in ["sign-in", "tabs", "accent", "composer-new"].enumerated() {
      if index == 0 {
        app.launchArguments = ["--ui-verify", "--ui-verify-offscreen", "--ui-verify-open", "lodymacverify://case/\(name)"]
        app.launch()
      } else {
        send(["lodymacverify://case/\(name)"])
      }
      let windows = app.windows.matching(identifier: "catalog-scene")
      XCTAssertTrue(windows.firstMatch.waitForExistence(timeout: 10), "scene \(name) opens")
      for window in windows.allElementsBoundByIndex {
        XCTAssertGreaterThan(window.frame.minX, edge, "\(name) window \(window.title) stays off every display")
      }
      XCTAssertFalse(app.windows["debug"].exists, "no Debug window appears")
    }
  }
}
