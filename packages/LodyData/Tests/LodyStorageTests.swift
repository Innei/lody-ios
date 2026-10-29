import XCTest
@testable import LodyData

final class LodyStorageTests: XCTestCase {
  func testMacStorageNeverSharesTheDesktopAppsSupportFolder() {
    let support = URL.applicationSupportDirectory.standardizedFileURL.path
    let root = LodyStorage.root.standardizedFileURL.path
    XCTAssertTrue(root.hasPrefix(support + "/"), root)
    XCTAssertNotEqual(root, support)
    XCTAssertFalse(LocalStore.defaultURL.path.hasPrefix(support + "/Lody/"), LocalStore.defaultURL.path)
  }
}
