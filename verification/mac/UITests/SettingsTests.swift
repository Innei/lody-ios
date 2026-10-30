import XCTest

final class SettingsTests: LodyMacUITestCase {
  private func control(_ identifier: String) -> XCUIElement {
    scene.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func show(_ page: String, expecting identifier: String) {
    control("settings-\(page)").click()
    XCTAssertTrue(control(identifier).waitForExistence(timeout: 5), "the \(page) page shows \(identifier)")
  }

  func testSidebarOpensEveryPageByClick() {
    open("settings", "light")
    let pages = [
      ("account", "settings-machine-m-studio"),
      ("general", "settings-general-queue"),
      ("appearance", "settings-appearance-theme-dark"),
      ("keyboard", "settings-keyboard-list"),
      ("workspace", "settings-workspace-name"),
      ("machines", "settings-machines-refresh"),
      ("projects", "settings-projects-share-m-studio:local:p1"),
      ("about", "settings-about-version"),
    ]
    for (page, identifier) in pages { show(page, expecting: identifier) }
  }

  func testGeneralAppearanceAndAboutInLightAndDark() {
    for appearance in ["light", "dark"] {
      open("settings", appearance)
      XCTAssertTrue(control("settings-general-queue").waitForExistence(timeout: 5))
      attach("settings-general-\(appearance)", scene)
      show("appearance", expecting: "settings-appearance-theme-dark")
      attach("settings-appearance-\(appearance)", scene)
      show("about", expecting: "settings-about-version")
      attach("settings-about-\(appearance)", scene)
    }
  }

  func testQueueSwitchesToSteer() {
    open("settings", "light")
    let queue = control("settings-general-queue")
    XCTAssertTrue(queue.waitForExistence(timeout: 5))
    let steer = queue.radioButtons["Steer"]
    XCTAssertEqual(queue.radioButtons["Queue"].value as? Int, 1, "the fixture starts on Queue")
    steer.click()
    eventually("the segment moves to Steer") { steer.value as? Int == 1 && queue.radioButtons["Queue"].value as? Int == 0 }
  }

  func testThemeAndAccentChoicesApply() {
    open("settings", "light")
    show("appearance", expecting: "settings-appearance-theme-dark")
    control("settings-appearance-theme-dark").click()
    eventually("Dark becomes the theme") {
      control("settings-appearance-theme-dark").isSelected && !control("settings-appearance-theme-system").isSelected
    }
    control("settings-appearance-accent-purple").click()
    eventually("the purple dot becomes the accent") { control("settings-appearance-accent-purple").isSelected }
    attach("settings-appearance-dark-purple", scene)
    control("settings-appearance-accent-system").click()
    eventually("the system accent comes back for later cases") { control("settings-appearance-accent-system").isSelected }
  }

  func testOnlyOwnedMachinesOfferRename() {
    open("settings", "light")
    show("machines", expecting: "settings-machines-rename-m-studio")
    XCTAssertFalse(control("settings-machines-rename-m-build").exists, "a machine you don't own has no Rename")
    XCTAssertTrue(scene.images.matching(NSPredicate(format: "label CONTAINS[c] 'owner'")).firstMatch.exists, "it shows the owner-only lock")
    attach("settings-machines-light", scene)
  }

  func testOwnedProjectShareToggleFlips() {
    open("settings", "light")
    show("projects", expecting: "settings-projects-share-m-studio:local:p2")
    let share = control("settings-projects-share-m-studio:local:p2")
    XCTAssertEqual(share.value as? Int, 0, "handbook starts private")
    share.click()
    eventually("sharing turns on") { share.value as? Int == 1 }
    XCTAssertFalse(control("settings-projects-share-m-build:local:p3").exists, "another member's project has no toggle")
  }

  func testAboutShowsTheLicensesSheet() {
    open("settings", "light")
    show("about", expecting: "settings-about-licenses")
    control("settings-about-licenses").click()
    let sheet = app.descendants(matching: .any).matching(identifier: "settings-about-licenses-sheet").firstMatch
    XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Show… opens the licenses sheet")
    attach("settings-licenses-light", scene)
    scene.buttons["Done"].click()
    eventually("Done closes the sheet") { !sheet.exists }
  }
}
