import LodyData
import XCTest
@testable import LodyMacApp

@MainActor
final class MacMachinesSettingsTests: XCTestCase {
  private var renames: [(String, String, String)] = []
  private var loads: [String] = []

  private func list() -> MacMachineList {
    var machines = [
      MacMachine(id: "m-studio", name: "Studio", detail: "macOS", readOnly: false),
      MacMachine(id: "m-shared", name: "Build Box", detail: "linux", readOnly: true),
    ]
    return MacMachineList(services: MacMachineServices(
      load: { workspace in
        self.loads.append(workspace)
        return machines
      },
      rename: { workspace, machine, name in
        self.renames.append((workspace, machine.id, name))
        machines[0].name = name
        return machines
      },
      presence: { .unknown }
    ))
  }

  func testOwnersRenameTheirMachineAndTheRowUpdates() async throws {
    let list = list()
    await list.load(workspaceId: "w1")
    let studio = try XCTUnwrap(list.rows.first)
    XCTAssertTrue(studio.canRename)
    await list.rename(studio, to: "  Studio Pro ", workspaceId: "w1")
    XCTAssertEqual(renames.map(\.1), ["m-studio"])
    XCTAssertEqual(renames.map(\.2), ["Studio Pro"])
    XCTAssertEqual(list.rows.first?.name, "Studio Pro")
  }

  func testSharedMachinesCannotBeRenamed() async throws {
    let list = list()
    await list.load(workspaceId: "w1")
    let shared = try XCTUnwrap(list.rows.last)
    XCTAssertFalse(shared.canRename)
    await list.rename(shared, to: "Mine", workspaceId: "w1")
    XCTAssertTrue(renames.isEmpty)
  }

  func testSwitchingBackToAWorkspaceShowsItsCachedRowsWhileLoading() async {
    let list = list()
    await list.load(workspaceId: "w1")
    list.show(workspaceId: "w2")
    XCTAssertTrue(list.rows.isEmpty)
    list.show(workspaceId: "w1")
    XCTAssertEqual(list.rows.map(\.id), ["m-studio", "m-shared"])
  }
}
