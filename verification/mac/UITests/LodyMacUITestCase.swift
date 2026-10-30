import XCTest

@MainActor
class LodyMacUITestCase: XCTestCase {
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
  }

  override func tearDown() async throws {
    if (testRun?.totalFailureCount ?? 0) > 0 { attach("failure-\(name)") }
    app.terminate()
  }

  var scene: XCUIElement { app.windows.matching(identifier: "catalog-scene").firstMatch }

  func open(_ name: String, _ appearance: String) {
    if app.state != .notRunning { app.terminate() }
    app.launchArguments = [
      "--ui-verify",
      "--ui-verify-open", "lodymacverify://appearance/\(appearance)",
      "--ui-verify-open", "lodymacverify://case/\(name)",
    ]
    app.launch()
    XCTAssertTrue(scene.waitForExistence(timeout: 10), "scene \(name) opens")
  }

  func attach(_ name: String, _ element: XCUIElement? = nil) {
    let source: XCUIScreenshotProviding = element.flatMap { $0.exists ? $0 : nil } ?? XCUIScreen.main
    let attachment = XCTAttachment(screenshot: source.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

  func eventually(_ message: String, timeout: TimeInterval = 5, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      if Date() > deadline { return XCTFail(message) }
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
  }

  func choose(_ option: String, in popup: XCUIElement) {
    popup.click()
    let item = popup.menuItems[option]
    XCTAssertTrue(item.waitForExistence(timeout: 3), "menu offers \(option)")
    item.click()
  }
}
