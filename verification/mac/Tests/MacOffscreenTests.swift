import AppKit
import XCTest
@testable import LodyMacApp

@MainActor
final class MacOffscreenTests: XCTestCase {
  private let screens = [NSRect(x: 0, y: 0, width: 1440, height: 900), NSRect(x: -1920, y: 0, width: 1920, height: 1080)]

  func testFramesOnAnyDisplayMoveBeyondEveryDisplay() {
    let frames = [
      NSRect(x: 100, y: 100, width: 800, height: 600),
      NSRect(x: -1800, y: 50, width: 1100, height: 720),
      NSRect(x: 1400, y: 880, width: 300, height: 200),
      NSRect(x: -2400, y: -300, width: 900, height: 700),
    ]
    for frame in frames {
      let parked = MacOffscreen.frame(frame, avoiding: screens)
      XCTAssertFalse(screens.contains { $0.intersects(parked) }, "\(frame) → \(parked)")
      XCTAssertEqual(parked.size, frame.size)
    }
  }

  func testParkedFramesStayPutAndKeepTheirRelativeLayout() {
    let workspace = MacOffscreen.frame(NSRect(x: 100, y: 100, width: 800, height: 600), avoiding: screens)
    XCTAssertEqual(MacOffscreen.frame(workspace, avoiding: screens), workspace)
    let settings = MacOffscreen.frame(NSRect(x: 600, y: 400, width: 300, height: 200), avoiding: screens)
    XCTAssertEqual(settings.minX - workspace.minX, 500)
    XCTAssertEqual(settings.minY - workspace.minY, 300)
  }

  func testOffscreenWindowsRefuseToBeConstrainedOntoADisplay() {
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    let constrained = window.constrainFrameRect(NSRect(x: 0, y: 0, width: 600, height: 400), to: NSScreen.main)
    XCTAssertFalse(NSScreen.screens.contains { $0.frame.intersects(constrained) }, "\(constrained)")
  }

  func testEveryCatalogSceneBuildsOffscreenWindowsWhenAsked() {
    let previous = MacOffscreen.enabled
    MacOffscreen.enabled = true
    defer { MacOffscreen.enabled = previous }
    for scene in DebugSceneFactory.scenes {
      let windows = scene.build()
      XCTAssertTrue(windows.allSatisfy { $0 is MacOffscreenWindow }, scene.id)
      windows.forEach { $0.close() }
    }
  }

  func testOrdinaryWindowsUnlessAsked() {
    let previous = MacOffscreen.enabled
    defer { MacOffscreen.enabled = previous }
    MacOffscreen.enabled = false
    XCTAssertFalse(MacOffscreen.enabled)
    XCTAssertTrue(MacOffscreen.windowClass === NSWindow.self)
    MacOffscreen.enabled = true
    XCTAssertTrue(MacOffscreen.windowClass === MacOffscreenWindow.self)
  }
}
