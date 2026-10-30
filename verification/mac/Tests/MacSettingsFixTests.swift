import AppKit
import LodyData
import XCTest
@testable import LodyMacApp

@MainActor
final class MacSettingsFixTests: XCTestCase {
  func testMachinesWaitForTheRuntimeAndReloadWhenTheCatalogChanges() async throws {
    let changed = Notification.Name("MacSettingsFixTests.catalog")
    var ready = false
    let machines = MacMachineServices(
      load: { _ in
        guard ready else { throw DataRuntime.failure("not_ready", "syncing") }
        return [MacMachine(id: "m1", name: "Studio", detail: nil, readOnly: false)]
      },
      rename: { _, _, _ in [] },
      presence: { .unknown }
    )
    let user = AuthUser(id: "u", name: "Innei", email: "i@innei.dev", image: nil)
    let workspace = AuthWorkspace(id: "w1", name: "Lab", slug: "lab", image: nil)
    let state = SettingsState(account: AuthAccount(user: user, workspaces: [workspace]), workspace: workspace)
    let source = SettingsSource(changes: [changed], read: { state }, refresh: {}, logout: {})
    let defaults = UserDefaults(suiteName: "lody-mac-fix-\(UUID().uuidString)")!
    let model = MacSettingsModel(services: MacSettingsServices(source: source, selectWorkspace: { _ in }, signIn: {}, machines: machines), defaults: defaults)
    await model.machines.load(workspaceId: "w1")
    XCTAssertFalse(model.machines.failed)
    XCTAssertTrue(model.machines.waiting)
    ready = true
    NotificationCenter.default.post(name: changed, object: nil)
    let deadline = Date().addingTimeInterval(2)
    while model.machines.rows.isEmpty, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
    XCTAssertEqual(model.machines.rows.map(\.id), ["m1"])
    XCTAssertFalse(model.machines.waiting)
  }

  private final class Gate {
    var waiting: [String: CheckedContinuation<Void, Never>] = [:]
    func open(_ id: String) { waiting.removeValue(forKey: id)?.resume() }
  }

  private func settle() async {
    for _ in 0..<20 { await Task.yield() }
  }

  func testAnOlderWorkspacesMembersNeverReplaceTheCurrentOnes() async {
    let gate = Gate()
    let model = MacWorkspaceModel(services: MacWorkspaceServices(
      members: { id in
        await withCheckedContinuation { gate.waiting[id] = $0 }
        return WorkspaceMembers(members: [.init(id: id, name: id, email: "\(id)@x", role: "owner")], role: id == "w1" ? "owner" : "member")
      },
      rename: { _, _ in }, setIcon: { _, _ in }, pickIcon: { nil }
    ))
    let first = Task { await model.load(workspaceId: "w1") }
    await settle()
    let second = Task { await model.load(workspaceId: "w2") }
    await settle()
    gate.open("w2")
    await second.value
    gate.open("w1")
    await first.value
    XCTAssertEqual(model.members.map(\.id), ["w2"])
    XCTAssertFalse(model.canEdit)
  }

  func testAnOlderWorkspacesProjectsNeverReplaceTheCurrentOnes() async {
    let gate = Gate()
    let model = MacProjectsModel(services: MacProjectServices(
      workspace: {
        SettingsWorkspace(userId: "u", workspaceId: "w", catalog: SettingsCatalog(projects: [
          SettingsProject(id: "m:local:a", machineId: "m", name: "a", rootPath: "/a"),
        ]))
      },
      list: { id in
        await withCheckedContinuation { gate.waiting[id] = $0 }
        return MacVisibility(userId: "u", rows: [.init(machineId: "m", localProjectId: "a", ownerUserId: "u", sharedWithTeam: id == "w1", updatedAt: 0)])
      },
      share: { _, _, _ in MacVisibility(userId: "u", rows: []) }
    ))
    let first = Task { await model.load(workspaceId: "w1") }
    await settle()
    let second = Task { await model.load(workspaceId: "w2") }
    await settle()
    gate.open("w2")
    await second.value
    gate.open("w1")
    await first.value
    XCTAssertEqual(model.groups.first?.rows.first?.shared, false)
  }

  func testLoginItemStateIsReReadWhenLodyBecomesActive() {
    var status = MacLoginItem.Status.requiresApproval
    let model = MacGeneralModel(services: MacGeneralServices(
      queued: { "queue" }, saveQueued: { _ in }, notifications: { false }, setNotifications: { $0 },
      loginItem: MacLoginItem(status: { status }, register: {}, unregister: {}, openSystemSettings: {})
    ))
    XCTAssertTrue(model.needsApproval)
    status = .enabled
    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    XCTAssertFalse(model.needsApproval)
    XCTAssertTrue(model.login)
  }

  func testAFailedLoginRegistrationIsReported() {
    struct Failure: Error {}
    let model = MacGeneralModel(services: MacGeneralServices(
      queued: { "queue" }, saveQueued: { _ in }, notifications: { false }, setNotifications: { $0 },
      loginItem: MacLoginItem(status: { .disabled }, register: { throw Failure() }, unregister: {}, openSystemSettings: {})
    ))
    model.setLogin(true)
    XCTAssertFalse(model.login)
    XCTAssertTrue(model.loginFailed)
  }
}
