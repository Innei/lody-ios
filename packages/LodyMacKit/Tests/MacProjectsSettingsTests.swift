import LodyData
import XCTest
@testable import LodyMacKit

@MainActor
final class MacProjectsSettingsTests: XCTestCase {
  private let catalog = SettingsCatalog(
    projects: [
      SettingsProject(id: "m1:local:p1", machineId: "m1", name: "lody-ios", rootPath: "/Users/i/lody-ios"),
      SettingsProject(id: "m2:local:p2", machineId: "m2", name: "scratch", rootPath: "/tmp/scratch"),
      SettingsProject(id: "m0:local:p3", machineId: "m0", name: "handbook", rootPath: "/Users/i/handbook"),
      SettingsProject(id: "m1:local:p4", machineId: "m1", name: "notes", rootPath: "/Users/i/notes"),
    ],
    machineNames: ["m1": "Studio", "m0": "Air"]
  )
  private let visibility = MacVisibility(userId: "u", rows: [
    .init(machineId: "m1", localProjectId: "p1", ownerUserId: "u", sharedWithTeam: false, updatedAt: 1),
    .init(machineId: "m0", localProjectId: "p3", ownerUserId: "someone", sharedWithTeam: true, updatedAt: 1),
  ])

  func testProjectsGroupByMachineWithUnnamedMachinesLast() {
    let groups = MacProjectGroups.make(visibility: visibility, catalog: catalog, presence: .unknown)
    XCTAssertEqual(groups.map(\.name), ["Air", "Studio", "m2"])
    XCTAssertEqual(groups[1].rows.map(\.name), ["lody-ios", "notes"])
    XCTAssertEqual(groups[1].rows.map(\.shared), [false, nil])
    XCTAssertEqual(groups[1].rows.map(\.owned), [true, false])
    XCTAssertEqual(groups[0].rows.first?.owned, false)
  }

  private var shares: [(String, String, Bool)] = []

  private func model(fails: Bool) -> MacProjectsModel {
    let visibility = visibility
    let catalog = catalog
    return MacProjectsModel(services: MacProjectServices(
      workspace: { SettingsWorkspace(userId: "u", workspaceId: "w1", catalog: catalog) },
      list: { _ in visibility },
      share: { _, row, shared in
        self.shares.append((row.machineId, row.localProjectId, shared))
        if fails { throw CocoaError(.fileWriteUnknown) }
        var next = visibility
        next.rows[0].sharedWithTeam = shared
        return next
      }
    ))
  }

  func testSharingAProjectCallsTheServiceAndShowsTheResult() async throws {
    let model = model(fails: false)
    await model.load(workspaceId: "w1")
    let row = try XCTUnwrap(model.groups.flatMap(\.rows).first { $0.name == "lody-ios" })
    await model.setShared(row, true, workspaceId: "w1")
    XCTAssertEqual(shares.map(\.1), ["p1"])
    XCTAssertEqual(shares.map(\.2), [true])
    XCTAssertEqual(model.groups.flatMap(\.rows).first { $0.name == "lody-ios" }?.shared, true)
  }

  func testAFailedShareRevertsTheSwitch() async throws {
    let model = model(fails: true)
    await model.load(workspaceId: "w1")
    let row = try XCTUnwrap(model.groups.flatMap(\.rows).first { $0.name == "lody-ios" })
    await model.setShared(row, true, workspaceId: "w1")
    XCTAssertEqual(model.groups.flatMap(\.rows).first { $0.name == "lody-ios" }?.shared, false)
    XCTAssertTrue(model.shareFailed)
  }

  func testOthersProjectsCannotBeShared() async throws {
    let model = model(fails: false)
    await model.load(workspaceId: "w1")
    let row = try XCTUnwrap(model.groups.flatMap(\.rows).first { $0.name == "handbook" })
    await model.setShared(row, false, workspaceId: "w1")
    XCTAssertTrue(shares.isEmpty)
  }
}
