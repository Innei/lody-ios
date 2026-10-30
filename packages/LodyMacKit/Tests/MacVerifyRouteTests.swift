import AppKit
import XCTest
@testable import LodyMacKit

final class MacVerifyRouteTests: XCTestCase {
  private func route(_ string: String) -> MacVerifyRoute? { MacVerifyRoute(URL(string: string)!) }

  func testRoutesCoverScenesResetAppearanceAndDump() {
    XCTAssertEqual(route("lodymacverify://case/sign-in"), .scene("sign-in"))
    XCTAssertEqual(route("lodymacverify://reset"), .reset)
    XCTAssertEqual(route("lodymacverify://appearance/dark"), .appearance("dark"))
    XCTAssertEqual(route("lodymacverify://appearance/light"), .appearance("light"))
    XCTAssertEqual(route("lodymacverify://dump?out=/tmp/lody-mac/state.json"), .dump(URL(fileURLWithPath: "/tmp/lody-mac/state.json")))
  }

  func testRoutesRejectOtherSchemesAndMalformedInput() {
    XCTAssertNil(route("lody://case/sign-in"))
    XCTAssertNil(route("lodymacverify://other/sign-in"))
    XCTAssertNil(route("lodymacverify://case/../etc"))
    XCTAssertNil(route("lodymacverify://appearance/blue"))
    XCTAssertNil(route("lodymacverify://dump?out=relative.json"))
    XCTAssertNil(route("lodymacverify://dump?out=/tmp/state.txt"))
  }

  func testLaunchArgumentsCarryRoutesInOrder() {
    let arguments = [
      "/Applications/Lody.app/Contents/MacOS/Lody", "--ui-verify",
      "--ui-verify-open", "lodymacverify://appearance/dark",
      "--ui-verify-open", "lodymacverify://case/sidebar",
      "--ui-verify-open", "lody://case/sign-in",
      "--ui-verify-open",
    ]
    XCTAssertEqual(MacVerifyRoute.launch(arguments), [.appearance("dark"), .scene("sidebar")])
    XCTAssertEqual(MacVerifyRoute.launch(["Lody", "--ui-verify"]), [])
  }

  @MainActor
  func testEveryCatalogSceneBuildsWithoutAnAccount() {
    MacOffscreen.enabled = true
    defer { MacOffscreen.enabled = false }
    let ids = MacCatalog.scenes.map(\.id)
    XCTAssertTrue(ids.contains("sign-in"))
    XCTAssertTrue(ids.contains("accent"))
    for scene in MacCatalog.scenes {
      let windows = scene.build()
      XCTAssertFalse(windows.isEmpty, scene.id)
      XCTAssertTrue(windows.allSatisfy { $0.identifier?.rawValue == "catalog-scene" }, scene.id)
      windows.forEach { $0.close() }
    }
    XCTAssertNil(MacCatalog.scene("missing"))
  }
}

@MainActor
final class MacVerifyActionTests: XCTestCase {
  private final class Target: NSObject {
    var clicks = 0
    var chosen = ""
    @objc func click(_ sender: Any?) { clicks += 1 }
    @objc func choose(_ sender: NSPopUpButton) { chosen = sender.titleOfSelectedItem ?? "" }
  }

  func testActRoutesCarryASequenceAndTheirArguments() {
    let route = { (string: String) in MacVerifyRoute(URL(string: string)!) }
    XCTAssertEqual(route("lodymacverify://act/click?seq=3&text=Allow"), .act(3, .click("Allow")))
    XCTAssertEqual(route("lodymacverify://act/choose?seq=4&current=System&option=Purple"), .act(4, .choose(current: "System", option: "Purple")))
    XCTAssertEqual(route("lodymacverify://act/type?seq=5&field=Reply%E2%80%A6&text=Ship%20it"), .act(5, .type(field: "Reply…", text: "Ship it")))
    XCTAssertEqual(route("lodymacverify://act/key?seq=6&name=return"), .act(6, .key("return")))
    XCTAssertNil(route("lodymacverify://act/click?text=Allow"))
    XCTAssertNil(route("lodymacverify://act/key?seq=1&name=escape"))
  }

  func testActionsDriveTheControlsOfAWindow() throws {
    let target = Target()
    let button = NSButton(title: "Allow", target: target, action: #selector(Target.click(_:)))
    let popup = NSPopUpButton()
    popup.addItems(withTitles: ["System", "Purple"])
    popup.target = target
    popup.action = #selector(Target.choose(_:))
    let input = MacComposerTextView()
    input.placeholder = "Reply…"
    var sent = 0
    input.onSubmit = { sent += 1 }
    let stack = NSStackView(views: [button, popup, input])
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
    window.contentView = stack

    XCTAssertNil(MacVerifyActions.perform(.click("Allow"), in: window))
    XCTAssertEqual(target.clicks, 1)
    XCTAssertNil(MacVerifyActions.perform(.choose(current: "System", option: "Purple"), in: window))
    XCTAssertEqual(target.chosen, "Purple")
    XCTAssertNil(MacVerifyActions.perform(.type(field: "Reply…", text: "Ship it"), in: window))
    XCTAssertEqual(input.string, "Ship it")
    XCTAssertNil(MacVerifyActions.perform(.key("return"), in: window))
    XCTAssertEqual(sent, 1)
    XCTAssertNotNil(MacVerifyActions.perform(.click("Missing"), in: window))
  }
}

@MainActor
final class MacSnapshotTests: XCTestCase {
  func testSnapshotRoutesAcceptOnlyAbsolutePNGPaths() {
    XCTAssertEqual(MacVerifyRoute(URL(string: "lodymacverify://snapshot?out=/tmp/a.png")!), .snapshot(URL(fileURLWithPath: "/tmp/a.png")))
    XCTAssertNil(MacVerifyRoute(URL(string: "lodymacverify://snapshot?out=a.png")!))
    XCTAssertNil(MacVerifyRoute(URL(string: "lodymacverify://snapshot?out=/tmp/a.json")!))
  }

  func testSnapshotsRenderTheWindowWithoutTheScreen() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = NSStackView(views: [NSTextField(labelWithString: "Hello")])
    let out = FileManager.default.temporaryDirectory.appending(path: "lody-snapshot-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: out) }
    try MacViewDump.snapshot(window, to: out)
    let image = try XCTUnwrap(NSImage(contentsOf: out))
    XCTAssertGreaterThanOrEqual(image.size.width, 320)
  }

  func testDumpedControlsCarryTheirRectFromTheWindowTopLeft() throws {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.borderless], backing: .buffered, defer: true)
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
    let popup = NSPopUpButton(frame: NSRect(x: 40, y: 30, width: 100, height: 20))
    root.addSubview(popup)
    window.contentView = root
    let node = MacViewDump.node(root)
    let child = try XCTUnwrap((node["children"] as? [[String: Any]])?.first)
    XCTAssertEqual(child["inWindow"] as? [Double], [40, 150, 100, 20])
  }
}

@MainActor
final class MacSceneResetTests: XCTestCase {
  func testResetRestoresTheSystemAccent() {
    let previous = MacAccent.current()
    defer { previous.save() }
    MacAccent.orange.save()
    MacSceneHost.shared.reset()
    XCTAssertEqual(MacAccent.current(), .system)
  }
}
