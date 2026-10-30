import XCTest
import LodyData

final class SessionDeletionTests: XCTestCase {
  private let sessions = [
    SessionItem(id: "s1", status: "idle", projectId: "w:p1"),
    SessionItem(id: "s1-tab", status: "completed", parentSessionId: "s1"),
    SessionItem(id: "s2", status: "running", projectId: "w:unassigned"),
    SessionItem(id: "s2-old", status: "running", archived: true, parentSessionId: "s2"),
  ]

  func testDeletingASessionTakesItsChildTabs() {
    XCTAssertEqual(SessionDeletion.targets(sessions, id: "s1").map(\.id), ["s1", "s1-tab"])
  }

  func testAnUnarchivedRunningSessionBlocksDeletion() {
    XCTAssertFalse(SessionDeletion.blocked(SessionDeletion.targets(sessions, id: "s1")))
    XCTAssertTrue(SessionDeletion.blocked(SessionDeletion.targets(sessions, id: "s2")))
    XCTAssertFalse(SessionDeletion.blocked([sessions[3]]))
  }

  func testOnlyProjectSessionsHaveAWorktree() {
    XCTAssertTrue(SessionDeletion.removesWorktree(sessions[0]))
    XCTAssertFalse(SessionDeletion.removesWorktree(sessions[2]))
  }
}
