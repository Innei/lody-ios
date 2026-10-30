import AppKit
import SwiftUI
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

@MainActor
final class MacSettingsModelTests: XCTestCase {
  private let user = AuthUser(id: "u", name: "Innei", email: "i@innei.dev", image: nil)
  private let lab = AuthWorkspace(id: "w1", name: "Innei Lab", slug: "lab", image: nil)
  private let side = AuthWorkspace(id: "w2", name: "Side", slug: "side", image: nil)

  private func model(_ state: SettingsState, selected: @escaping @MainActor (String) -> Void = { _ in }) -> MacSettingsModel {
    let source = SettingsSource(changes: [], read: { state }, refresh: {}, logout: {})
    let defaults = UserDefaults(suiteName: "lody-mac-settings-model-\(UUID().uuidString)")!
    return MacSettingsModel(services: MacSettingsServices(source: source, selectWorkspace: selected, signIn: {}), defaults: defaults)
  }

  func testChoosingAWorkspaceSelectsItEverywhere() {
    var chosen: [String] = []
    let model = model(SettingsState(account: AuthAccount(user: user, workspaces: [lab, side]), workspace: lab)) { chosen.append($0) }
    XCTAssertTrue(model.showsSwitcher)
    model.selectWorkspace("w2")
    XCTAssertEqual(chosen, ["w2"])
  }

  func testOneWorkspaceHidesTheSwitcher() {
    XCTAssertFalse(model(SettingsState(account: AuthAccount(user: user, workspaces: [lab]), workspace: lab)).showsSwitcher)
  }

  func testSignedOutHidesWorkspacePages() {
    let signedOut = model(SettingsState())
    XCTAssertFalse(signedOut.sections.map(\.section).contains(.workspace))
    let signedIn = model(SettingsState(account: AuthAccount(user: user, workspaces: [lab]), workspace: lab))
    XCTAssertTrue(signedIn.sections.map(\.section).contains(.workspace))
  }

  func testSearchNarrowsSectionsAndChoosingAPageIsRemembered() {
    let model = model(SettingsState(account: AuthAccount(user: user, workspaces: [lab]), workspace: lab))
    model.query = "theme"
    XCTAssertEqual(model.sections.flatMap(\.pages), [.appearance])
    model.selection = .machines
    XCTAssertEqual(MacSettingsPage.restored(model.defaults), .machines)
  }

  func testTheWindowHostsTheSettingsView() throws {
    let controller = MacSettingsWindow.make(model: model(SettingsState(account: AuthAccount(user: user, workspaces: [lab]), workspace: lab)))
    let window = try XCTUnwrap(controller.window)
    XCTAssertEqual(window.identifier?.rawValue, "settings")
    XCTAssertTrue(window.contentViewController is NSHostingController<MacSettingsView>)
    XCTAssertGreaterThanOrEqual(window.frame.width, 700)
    window.layoutIfNeeded()
  }

  func testTheWindowTitleFollowsThePage() throws {
    let model = model(SettingsState(account: AuthAccount(user: user, workspaces: [lab]), workspace: lab))
    model.selection = .appearance
    let window = try XCTUnwrap(MacSettingsWindow.make(model: model).window)
    window.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(window.title, MacSettingsPage.appearance.title)
    model.selection = .keyboard
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(window.title, MacSettingsPage.keyboard.title)
  }
}


@MainActor
final class MacGeneralSettingsTests: XCTestCase {
  private final class Box {
    var queued = "queue"
    var notifications = false
    var grant = true
    var login = MacLoginItem.Status.disabled
    var calls: [String] = []
  }

  private func model(_ box: Box) -> MacGeneralModel {
    MacGeneralModel(services: MacGeneralServices(
      queued: { box.queued },
      saveQueued: { box.queued = $0 },
      notifications: { box.notifications },
      setNotifications: { on in
        box.notifications = on && box.grant
        return box.notifications
      },
      loginItem: MacLoginItem(
        status: { box.login },
        register: { box.calls.append("register"); box.login = .requiresApproval },
        unregister: { box.calls.append("unregister"); box.login = .disabled },
        openSystemSettings: { box.calls.append("open") }
      )
    ))
  }

  func testSteerSavesGuide() {
    let box = Box()
    let model = model(box)
    XCTAssertFalse(model.steer)
    model.steer = true
    XCTAssertEqual(box.queued, "guide")
    XCTAssertTrue(model.steer)
  }

  func testDeniedNotificationsLeaveTheSwitchOff() async {
    let box = Box()
    box.grant = false
    let model = model(box)
    await model.setNotifications(true)
    XCTAssertFalse(model.notifications)
  }

  func testLoginItemRegistersAndSurfacesApproval() {
    let box = Box()
    let model = model(box)
    model.setLogin(true)
    XCTAssertEqual(box.calls, ["register"])
    XCTAssertTrue(model.login)
    XCTAssertTrue(model.needsApproval)
    model.openLoginItems()
    model.setLogin(false)
    XCTAssertEqual(box.calls, ["register", "open", "unregister"])
    XCTAssertFalse(model.login)
  }
}
