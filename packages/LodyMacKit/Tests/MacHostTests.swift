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
}
