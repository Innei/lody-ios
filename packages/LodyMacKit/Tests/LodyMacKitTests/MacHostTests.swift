import XCTest
import LodyData
@testable import LodyMacKit

@MainActor
final class MacHostTests: XCTestCase {
  func testMacNeverSuspendsTheRuntimeWhenNotFrontmost() {
    let host = MacHost(frontmost: { false })
    XCTAssertFalse(host.isBackground)
    XCTAssertTrue(host.isActive)
  }

  func testSendsAlwaysGetAnAllowanceOnMac() {
    let host = MacHost(frontmost: { false })
    let token = host.beginSendAllowance(expired: {})
    XCTAssertNotNil(token)
    if let token { host.endSendAllowance(token) }
  }
}
