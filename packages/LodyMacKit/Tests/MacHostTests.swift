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
}
