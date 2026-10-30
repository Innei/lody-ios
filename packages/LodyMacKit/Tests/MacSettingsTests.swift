import AppKit
import XCTest
import LodyData
@testable import LodyMacKit

@MainActor
final class MacSettingsPageTests: XCTestCase {
  func testSectionsFollowTheDesktopOrder() {
    XCTAssertEqual(MacSettingsPage.Section.personal.pages, [.general, .appearance, .keyboard])
    XCTAssertEqual(MacSettingsPage.Section.workspace.pages, [.workspace, .machines, .projects])
    XCTAssertEqual(MacSettingsPage.Section.other.pages.first, .about)
  }

  func testSearchMatchesTitlesAndRowLabels() {
    XCTAssertEqual(MacSettingsPage.matching(""), MacSettingsPage.allCases)
    XCTAssertEqual(MacSettingsPage.matching("notif"), [.general])
    XCTAssertEqual(MacSettingsPage.matching("LOGIN"), [.general])
    XCTAssertEqual(MacSettingsPage.matching("theme"), [.appearance])
    XCTAssertTrue(MacSettingsPage.matching("keyboard").contains(.keyboard))
    XCTAssertEqual(MacSettingsPage.matching("zzz"), [])
  }

  func testTheLastPageIsRememberedAndUnknownValuesFallBackToGeneral() {
    let defaults = UserDefaults(suiteName: "lody-mac-settings-\(UUID().uuidString)")!
    XCTAssertEqual(MacSettingsPage.restored(defaults), .general)
    MacSettingsPage.remember(.machines, defaults)
    XCTAssertEqual(MacSettingsPage.restored(defaults), .machines)
    defaults.set("billing", forKey: MacSettingsPage.key)
    XCTAssertEqual(MacSettingsPage.restored(defaults), .general)
  }

  func testEveryPageHasATitleAndATile() {
    for page in MacSettingsPage.allCases {
      XCTAssertFalse(page.title.isEmpty, "\(page)")
      XCTAssertFalse(page.symbol.isEmpty, "\(page)")
    }
  }
}
