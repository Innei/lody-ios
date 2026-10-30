import XCTest

final class TabsTests: LodyMacUITestCase {
  func testNativeTabsCarrySessionTitlesAndBackgroundBadges() {
    for appearance in ["light", "dark"] {
      open("tabs", appearance)
      let tabs = scene.tabGroups.firstMatch.tabs
      eventually("three tabs open") { tabs.count == 3 }
      XCTAssertEqual(tabs.allElementsBoundByIndex.map(\.title), [
        "Catalog · Build the AppKit sidebar", "Catalog · Landing page copy", "Catalog · Q4 roadmap",
      ])
      let badges = tabs.allElementsBoundByIndex.map { tab in
        tab.images.matching(NSPredicate(format: "identifier BEGINSWITH 'tab-badge-'")).allElementsBoundByIndex.first?.identifier ?? ""
      }
      XCTAssertEqual(badges, ["tab-badge-working", "tab-badge-approval", ""], "background tabs show working and approval badges")
      attach("tabs-\(appearance)", scene)
    }
    let tabs = scene.tabGroups.firstMatch.tabs
    tabs.element(boundBy: 1).click()
    eventually("clicking a tab selects it") { tabs.element(boundBy: 1).value as? Int == 1 }
  }
}
