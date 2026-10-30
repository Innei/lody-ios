import XCTest
import LodyData

final class WorkspaceMembersTests: XCTestCase {
  private let organization: [String: Any] = [
    "id": "w1",
    "members": [
      ["id": "mem1", "userId": "u1", "role": "owner", "user": ["id": "u1", "name": "Innei", "email": "i@innei.dev", "image": "https://x/a.png", "token": "secret"]],
      ["id": "mem2", "userId": "u2", "role": "member", "user": ["id": "u2", "name": "", "email": "sam@example.com"]],
      ["id": "mem3", "userId": "u3", "role": "admin, member", "user": ["id": "u3", "name": "Ada", "email": "ada@example.com"]],
    ],
  ]

  @MainActor
  func testAFullOrganizationProjectsToMembersAndTheCallersRole() throws {
    let projected = try WorkspaceMembers.project(organization, workspace: "w1", user: "u3")
    let data = try JSONSerialization.data(withJSONObject: projected)
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret"))
    let members = try JSONDecoder().decode(WorkspaceMembers.self, from: data)
    XCTAssertEqual(members.members.map(\.email), ["i@innei.dev", "sam@example.com", "ada@example.com"])
    XCTAssertEqual(members.members.map(\.role), ["owner", "member", "admin, member"])
    XCTAssertEqual(members.members.first?.image, "https://x/a.png")
    XCTAssertEqual(members.role, "admin, member")
    XCTAssertTrue(members.canEdit)
  }

  @MainActor
  func testPlainMembersAndAnotherOrganizationCannotEdit() throws {
    let member = try JSONDecoder().decode(
      WorkspaceMembers.self, from: JSONSerialization.data(withJSONObject: WorkspaceMembers.project(organization, workspace: "w1", user: "u2"))
    )
    XCTAssertFalse(member.canEdit)
    XCTAssertThrowsError(try WorkspaceMembers.project(organization, workspace: "w2", user: "u1"))
  }
}
