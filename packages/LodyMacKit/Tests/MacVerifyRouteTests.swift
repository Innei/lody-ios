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

  @MainActor
  func testEveryCatalogSceneBuildsWithoutAnAccount() {
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
