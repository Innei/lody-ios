import XCTest
import LodyCore
import LodyData
@testable import LodyMacApp

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

@MainActor
final class MacComposerLayoutTests: XCTestCase {
  func testAReplySendTellsTheTranscriptBeforeTheServiceRuns() throws {
    final class Events { var log: [String] = [] }
    let events = Events()
    var model = MacComposerModel(mode: .reply)
    model.replyReady = true
    model.text = "Ship it"
    let controller = MacComposerController(model: model, service: MacComposerService(
      options: { _, _ in throw OutboxError.scopeExpired }, create: { _, _ in },
      reply: { _, _ in events.log.append("reply") }
    ))
    controller.onSend = { events.log.append("send") }
    let input = try XCTUnwrap(controller.view.descendants(MacComposerTextView.self).first)
    input.onSubmit?()
    XCTAssertEqual(events.log, ["send", "reply"])
  }

  func testABlockedNewSessionKeepsItsChipsAndNoticeInsideTheComposer() throws {
    var model = MacComposerModel(mode: .newSession)
    let handbook = CreateProject(id: "p3", machineId: "", name: "handbook")
    model.form = CreateSessionForm(userId: "u", workspaceId: "w", projects: [handbook])
    model.form.open(projectId: nil, context: nil)
    model.form.selectProject(handbook)
    model.text = "Ship the Mac sidebar"
    XCTAssertEqual(model.missing, .machine)
    let composer = MacComposerView(frame: NSRect(x: 0, y: 0, width: 452, height: 160))
    composer.translatesAutoresizingMaskIntoConstraints = false
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 452, height: 300), styleMask: [.titled], backing: .buffered, defer: true)
    let root = NSView()
    window.contentView = root
    root.addSubview(composer)
    NSLayoutConstraint.activate([
      composer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      composer.widthAnchor.constraint(equalToConstant: 452),
      composer.topAnchor.constraint(equalTo: root.topAnchor),
    ])
    composer.render(model, reply: ("", "", ""))
    root.layoutSubtreeIfNeeded()
    XCTAssertFalse(composer.notice.isHidden)
    for view in [composer.project, composer.machine, composer.agent, composer.notice] {
      let frame = view.convert(view.bounds, to: composer)
      XCTAssertLessThanOrEqual(frame.maxX, 452 - 10 + 0.5, "\(view.accessibilityIdentifier()) stays inside the trailing padding")
      XCTAssertGreaterThanOrEqual(frame.minX, 4, "\(view.accessibilityIdentifier()) keeps its leading padding")
    }
  }
}


@MainActor
final class MacNewSessionCatalogTests: XCTestCase {
  private static let changed = Notification.Name("mac-new-session-test-catalog")

  private func wait(until condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(2)
    while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
  }

  func testAFailedOptionsLoadRetriesWhenTheCatalogChanges() {
    var state = SessionListState(userId: "u", workspaceId: "w", catalog: SessionCatalog(projects: [SessionProject(id: "p1", name: "lody-ios")]))
    var calls = 0
    let service = MacComposerService(options: { _, _ in
      calls += 1
      throw OutboxError.scopeExpired
    }, create: { _, _ in })
    let source = MacSessionsSource(changes: [Self.changed], read: { state }, write: { _, _, _ in }, selectWorkspace: { _ in })
    let controller = MacNewSessionController(source: source, service: service)
    _ = controller.view
    wait { calls == 1 }
    state.presence = SettingsMachinePresence(state: "live", onlineMachineIds: [])
    NotificationCenter.default.post(name: Self.changed, object: nil)
    wait { calls == 2 }
    XCTAssertEqual(calls, 2)
  }

  func testProjectsAddedToTheCatalogAppearInThePicker() throws {
    var state = SessionListState(userId: "u", workspaceId: "w", catalog: SessionCatalog(projects: [SessionProject(id: "p1", name: "lody-ios")]))
    let service = MacComposerService(options: { _, _ in throw OutboxError.scopeExpired }, create: { _, _ in })
    let source = MacSessionsSource(changes: [Self.changed], read: { state }, write: { _, _, _ in }, selectWorkspace: { _ in })
    let controller = MacNewSessionController(source: source, service: service)
    _ = controller.view
    state.catalog.projects.append(SessionProject(id: "p2", name: "handbook"))
    NotificationCenter.default.post(name: Self.changed, object: nil)
    let picker = try XCTUnwrap(controller.view.descendants(NSPopUpButton.self).first { $0.accessibilityIdentifier() == "composer-project" })
    XCTAssertTrue(picker.itemTitles.contains("handbook"))
    XCTAssertEqual(picker.titleOfSelectedItem, "lody-ios")
  }
}
