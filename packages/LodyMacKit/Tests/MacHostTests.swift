import AppKit
import XCTest
import LodyData
@testable import LodyMacKit

@MainActor
final class MacHostTests: XCTestCase {
  func testMacNeverSuspendsTheRuntimeWhenNotFrontmost() {
    let host = MacHost()
    XCTAssertFalse(host.isBackground)
    XCTAssertTrue(host.isActive)
  }

  func testSendsAlwaysGetAnAllowanceOnMac() {
    let host = MacHost()
    let token = host.beginSendAllowance(expired: {})
    XCTAssertNotNil(token)
    if let token { host.endSendAllowance(token) }
  }

  func testMemoryPressureWarningsReachTheRuntime() {
    let host = MacHost()
    var posted = 0
    let observer = NotificationCenter.default.addObserver(forName: .lodyHostDidReceiveMemoryWarning, object: nil, queue: nil) { _ in posted += 1 }
    defer { NotificationCenter.default.removeObserver(observer) }
    host.memoryPressure(.normal)
    XCTAssertEqual(posted, 0)
    host.memoryPressure(.warning)
    host.memoryPressure(.critical)
    XCTAssertEqual(posted, 2)
  }

  func testAlertsWithoutAWindowWaitForTheNextKeyWindow() {
    var window: NSWindow?
    var shown: [String] = []
    var finish: (() -> Void)?
    let host = MacHost(keyWindow: { window }, present: { alert, _, done in
      shown.append(alert.messageText)
      finish = done
    })
    host.alert(title: "Couldn't send", message: "Offline")
    host.alert(title: "Still offline", message: "Retry later")
    XCTAssertEqual(shown, [])
    window = NSWindow()
    NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
    XCTAssertEqual(shown, ["Couldn't send"])
    finish?()
    XCTAssertEqual(shown, ["Couldn't send", "Still offline"])
  }
}
