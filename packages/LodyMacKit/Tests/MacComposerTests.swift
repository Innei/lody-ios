import XCTest
import LodyCore
import LodyData
@testable import LodyMacKit

final class MacComposerTests: XCTestCase {
  private let project = CreateProject(id: "p1", machineId: "m1", name: "lody-ios")
  private let agent = CreationAgent(id: "claude", name: "Claude", machineId: "m1", machineName: "Mac Studio", cliType: "builtin", agentType: "claude")

  private func newSession() -> MacComposerModel {
    var model = MacComposerModel(mode: .newSession)
    model.form = CreateSessionForm(userId: "u", workspaceId: "w", projects: [])
    model.form.open(projectId: nil, context: nil)
    model.text = "Ship the sidebar"
    return model
  }

  func testNewSessionNeedsAProjectMachineAndAgentBeforeSending() {
    var model = newSession()
    XCTAssertEqual(model.missing, .project)
    XCTAssertFalse(model.canSend)

    model.form.selectProject(project)
    XCTAssertEqual(model.missing, .machine)
    XCTAssertFalse(model.canSend)

    var options = CreationOptions(sessionId: "s-new", project: project, agents: [agent], capabilities: [])
    options.agents = [agent]
    model.form.applyOptions(options, chat: false)
    model.form.selectMachine("m1")
    XCTAssertNil(model.missing)
    XCTAssertTrue(model.canSend)

    model.text = "   "
    XCTAssertFalse(model.canSend)
  }

  func testReplyOnlyNeedsTextAndAReadyOutbox() {
    var model = MacComposerModel(mode: .reply)
    model.text = "Looks good"
    XCTAssertFalse(model.canSend)
    model.replyReady = true
    XCTAssertNil(model.missing)
    XCTAssertTrue(model.canSend)
  }

  func testFullAccessModesAreFlaggedAsWarnings() {
    XCTAssertTrue(MacComposerModel.isFullAccess("bypassPermissions"))
    XCTAssertTrue(MacComposerModel.isFullAccess("danger-full-access"))
    XCTAssertFalse(MacComposerModel.isFullAccess("default"))
    XCTAssertFalse(MacComposerModel.isFullAccess("acceptEdits"))
  }
}
