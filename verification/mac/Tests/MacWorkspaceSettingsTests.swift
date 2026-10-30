import LodyData
import XCTest
@testable import LodyMacApp

@MainActor
final class MacWorkspaceSettingsTests: XCTestCase {
  private var renamed: [String] = []
  private var icons: [URL] = []

  private func model(role: String?) -> MacWorkspaceModel {
    let members = WorkspaceMembers(members: [.init(id: "u", name: "Innei", email: "i@innei.dev", role: role ?? "member")], role: role)
    return MacWorkspaceModel(services: MacWorkspaceServices(
      members: { _ in
        guard role != nil else { throw CocoaError(.fileReadUnknown) }
        return members
      },
      rename: { _, name in self.renamed.append(name) },
      setIcon: { _, url in self.icons.append(url) },
      pickIcon: { URL(fileURLWithPath: "/tmp/icon.png") }
    ))
  }

  func testOwnersCanRenameAndChangeTheIcon() async {
    let model = model(role: "owner")
    await model.load(workspaceId: "w1")
    XCTAssertTrue(model.canEdit)
    await model.rename("w1", to: "  New Lab  ")
    await model.chooseIcon("w1")
    XCTAssertEqual(renamed, ["New Lab"])
    XCTAssertEqual(icons.map(\.lastPathComponent), ["icon.png"])
    XCTAssertEqual(model.members.map(\.email), ["i@innei.dev"])
  }

  func testMembersAndAnUnknownRoleAreReadOnly() async {
    for role in ["member", nil] {
      let model = model(role: role)
      await model.load(workspaceId: "w1")
      XCTAssertFalse(model.canEdit)
      await model.rename("w1", to: "Nope")
      await model.chooseIcon("w1")
    }
    XCTAssertEqual(renamed, [])
    XCTAssertEqual(icons, [])
  }

  func testAnEmptyNameIsIgnored() async {
    let model = model(role: "admin")
    await model.load(workspaceId: "w1")
    await model.rename("w1", to: "   ")
    XCTAssertEqual(renamed, [])
  }
}
