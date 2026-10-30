import XCTest

@MainActor
class LodyMacUITestCase: XCTestCase {
  private static var sequence = 0
  let app = XCUIApplication()

  override func setUp() async throws {
    continueAfterFailure = false
  }

  override func tearDown() async throws {
    if (testRun?.totalFailureCount ?? 0) > 0, app.state != .notRunning {
      attach("failure-\(name)")
      let tree = XCTAttachment(string: app.debugDescription)
      tree.name = "failure-tree-\(name)"
      tree.lifetime = .keepAlways
      add(tree)
      app.terminate()
    }
  }

  nonisolated override class func tearDown() {
    MainActor.assumeIsolated { XCUIApplication().terminate() }
    super.tearDown()
  }

  var scene: XCUIElement { app.windows.matching(identifier: "catalog-scene").firstMatch }

  func open(_ name: String, _ appearance: String) {
    let routes = ["lodymacverify://appearance/\(appearance)", "lodymacverify://case/\(name)"]
    if app.state == .notRunning {
      app.launchArguments = ["--ui-verify"] + routes.flatMap { ["--ui-verify-open", $0] }
      app.launch()
    } else {
      send(["lodymacverify://reset"] + routes)
    }
    XCTAssertTrue(scene.waitForExistence(timeout: 10), "scene \(name) opens")
  }

  func send(_ routes: [String]) {
    Self.sequence += 1
    let seq = String(Self.sequence)
    let center = DistributedNotificationCenter.default()
    let opened = XCTNSNotificationExpectation(
      name: Notification.Name("app.innei.lody.mac.verify.opened"), object: seq, notificationCenter: center
    )
    center.postNotificationName(
      Notification.Name("app.innei.lody.mac.verify.open"), object: ([seq] + routes).joined(separator: " "),
      userInfo: nil, deliverImmediately: true
    )
    wait(for: [opened], timeout: 10)
  }

  func attach(_ name: String, _ element: XCUIElement? = nil) {
    let source: XCUIScreenshotProviding = element.flatMap { $0.exists ? $0 : nil } ?? XCUIScreen.main
    let attachment = XCTAttachment(screenshot: source.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func value(_ element: XCUIElement) -> String { element.value as? String ?? "" }

  func eventually(_ message: @autoclosure () -> String, timeout: TimeInterval = 5, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
      if Date() > deadline { return XCTFail(message()) }
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
