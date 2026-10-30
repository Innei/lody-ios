import LodyData
import XCTest
@testable import LodyMacKit

@MainActor
final class MacMachineListTests: XCTestCase {
  func testRowsCarryOwnershipAndPresence() async {
    let machines = [
      MacMachine(id: "m-studio", name: "Studio", detail: "macOS", readOnly: false),
      MacMachine(id: "m-shared", name: "Build Box", detail: "linux", readOnly: true),
      MacMachine(id: "m-mini", name: "Mini", detail: nil, readOnly: false),
    ]
    var loaded: [String] = []
    let list = MacMachineList(services: MacMachineServices(
      load: { workspace in
        loaded.append(workspace)
        return machines
      },
      rename: { _, _, _ in machines },
      presence: { SettingsMachinePresence(state: "live", onlineMachineIds: ["m-studio"]) }
    ))
    await list.load(workspaceId: "w1")
    XCTAssertEqual(loaded, ["w1"])
    XCTAssertEqual(list.rows.map(\.status), ["online", "offline", "offline"])
    XCTAssertEqual(list.owned.map(\.id), ["m-studio", "m-mini"])
  }

  func testAFailedLoadKeepsTheErrorAndNoRows() async {
    struct Failure: Error {}
    let list = MacMachineList(services: MacMachineServices(
      load: { _ in throw Failure() }, rename: { _, _, _ in [] }, presence: { .unknown }
    ))
    await list.load(workspaceId: "w1")
    XCTAssertTrue(list.rows.isEmpty)
    XCTAssertTrue(list.failed)
  }
}

@MainActor
final class MacAccountSettingsTests: XCTestCase {
  private func model(logout: @escaping @MainActor () async -> Void) -> MacSettingsModel {
    let user = AuthUser(id: "u", name: "Innei", email: "i@innei.dev", image: nil)
    let workspace = AuthWorkspace(id: "w1", name: "Lab", slug: "lab", image: nil)
    let state = SettingsState(account: AuthAccount(user: user, workspaces: [workspace]), workspace: workspace)
    let source = SettingsSource(changes: [], read: { state }, refresh: {}, logout: logout)
    let defaults = UserDefaults(suiteName: "lody-mac-account-\(UUID().uuidString)")!
    return MacSettingsModel(services: MacSettingsServices(source: source, selectWorkspace: { _ in }, signIn: {}), defaults: defaults)
  }

  func testConfirmingSignOutLogsOutOnce() async {
    var calls = 0
    let model = model { calls += 1 }
    model.requestSignOut()
    XCTAssertTrue(model.confirmingSignOut)
    await model.confirmSignOut()
    XCTAssertEqual(calls, 1)
    XCTAssertFalse(model.confirmingSignOut)
  }

  func testCancellingSignOutKeepsTheAccount() {
    var calls = 0
    let model = model { calls += 1 }
    model.requestSignOut()
    model.cancelSignOut()
    XCTAssertEqual(calls, 0)
    XCTAssertFalse(model.confirmingSignOut)
  }
}
