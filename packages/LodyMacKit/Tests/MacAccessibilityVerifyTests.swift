import AppKit
import SwiftUI
import XCTest
@testable import LodyMacKit

@MainActor
final class MacAccessibilityVerifyTests: XCTestCase {
  private final class Box { var presses = 0 }

  private func window(_ box: Box) -> NSWindow {
    MacAccessibilityTree.enable()
    let view = Form {
      Button("Hello") { box.presses += 1 }
        .accessibilityIdentifier("hello-button")
      Toggle("Fill window width", isOn: .constant(true))
        .accessibilityIdentifier("hello-toggle")
    }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentViewController = NSHostingController(rootView: view)
    window.contentView?.layoutSubtreeIfNeeded()
    window.displayIfNeeded()
    return window
  }

  private func elements(_ node: [String: Any]) -> [[String: Any]] {
    let own = (node["elements"] as? [[String: Any]]) ?? []
    let nested = own.flatMap(elements)
    let children = ((node["children"] as? [[String: Any]]) ?? []).flatMap(elements)
    return own + nested + children
  }

  func testTheDumpListsHostedSwiftUIControls() throws {
    let window = window(Box())
    let root = try XCTUnwrap(window.contentView)
    let found = elements(MacViewDump.node(root))
    let button = try XCTUnwrap(found.first { $0["identifier"] as? String == "hello-button" })
    XCTAssertEqual(button["label"] as? String, "Hello")
    XCTAssertNotNil(found.first { $0["identifier"] as? String == "hello-toggle" })
  }

  func testClickPressesAHostedControlByIdentifier() {
    let box = Box()
    let window = window(box)
    XCTAssertNil(MacVerifyActions.perform(.click("hello-button"), in: window))
    XCTAssertEqual(box.presses, 1)
  }
}
