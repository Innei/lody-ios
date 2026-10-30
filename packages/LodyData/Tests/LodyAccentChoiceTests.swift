import XCTest
@testable import LodyData

final class LodyAccentChoiceTests: XCTestCase {
  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: "accentColor")
    super.tearDown()
  }

  func testUnsetAccentDefaultsToLody() {
    UserDefaults.standard.removeObject(forKey: "accentColor")
    XCTAssertEqual(LodyAccentChoice.current, .lody)
  }

  func testLodyRoundTripsThroughItsRawValue() {
    XCTAssertEqual(LodyAccentChoice(rawValue: "lody"), .lody)
    XCTAssertEqual(LodyAccentChoice.lody.rawValue, "lody")
  }

  func testStoredInkIsKept() {
    UserDefaults.standard.set("ink", forKey: "accentColor")
    XCTAssertEqual(LodyAccentChoice.current, .ink)
  }
}
