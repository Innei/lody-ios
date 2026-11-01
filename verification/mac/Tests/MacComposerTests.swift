import AppKit
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
  func testPrimaryActionStaysSquareWithMatchingCompactBottomAndRightInsets() throws {
    let composer = MacComposerView()
    composer.translatesAutoresizingMaskIntoConstraints = false
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let root = NSView()
    window.contentView = root
    root.addSubview(composer)
    NSLayoutConstraint.activate([composer.leadingAnchor.constraint(equalTo: root.leadingAnchor), composer.bottomAnchor.constraint(equalTo: root.bottomAnchor), composer.widthAnchor.constraint(equalToConstant: 680)])
    var model = MacComposerModel(mode: .reply)
    model.replyReady = true
    model.text = "Send"
    composer.render(model, reply: ("", "", ""))
    root.layoutSubtreeIfNeeded()
    let surface = try XCTUnwrap(composer.descendants(NSGlassEffectView.self).first)
    let button = composer.send.convert(composer.send.bounds, to: surface)
    XCTAssertEqual(button.width, button.height, accuracy: 0.5)
    let right = surface.bounds.maxX - button.maxX
    let bottom = surface.isFlipped ? surface.bounds.maxY - button.maxY : button.minY
    XCTAssertEqual(right, bottom, accuracy: 1)
    XCTAssertLessThanOrEqual(right, 10)
  }

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

  func testNewSessionKeepsProjectChoicesOutsideTheWritingSurface() throws {
    let composer = MacComposerView(frame: NSRect(x: 0, y: 0, width: 680, height: 220))
    var model = MacComposerModel(mode: .newSession)
    model.form = CreateSessionForm(userId: "u", workspaceId: "w", projects: [CreateProject(id: "p", machineId: "m", name: "lody-ios")])
    model.form.open(projectId: nil, context: nil)
    composer.render(model, reply: ("", "", ""))
    let surface = try XCTUnwrap(composer.descendants(NSGlassEffectView.self).first)
    XCTAssertFalse(composer.project.isDescendant(of: surface), "project choices describe the draft context outside the editor")
    XCTAssertTrue(composer.input.isDescendant(of: surface))
    composer.layoutSubtreeIfNeeded()
    XCTAssertGreaterThanOrEqual(composer.input.enclosingScrollView?.frame.height ?? 0, 36, "the writing area accommodates more than one native text line")
  }

  func testContextGlyphIsCenteredInTheMaterialVisibleAboveTheGlass() throws {
    let composer = MacComposerView()
    composer.translatesAutoresizingMaskIntoConstraints = false
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let root = NSView()
    window.contentView = root
    root.addSubview(composer)
    NSLayoutConstraint.activate([
      composer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      composer.topAnchor.constraint(equalTo: root.topAnchor),
      composer.widthAnchor.constraint(equalToConstant: 680),
    ])
    var model = MacComposerModel(mode: .newSession)
    model.form = CreateSessionForm(userId: "u", workspaceId: "w", projects: [CreateProject(id: "p", machineId: "m", name: "lody-ios")])
    model.form.open(projectId: nil, context: nil)
    composer.render(model, reply: ("", "", ""))
    root.layoutSubtreeIfNeeded()
    window.layoutIfNeeded()
    root.layoutSubtreeIfNeeded()
    let context = try XCTUnwrap(composer.descendants(NSVisualEffectView.self).first { $0.accessibilityIdentifier() == "composer-context-bar" })
    let surface = try XCTUnwrap(composer.descendants(NSGlassEffectView.self).first)
    let glyph = composer.agent.convert(try XCTUnwrap(composer.agent.cell).imageRect(forBounds: composer.agent.bounds), to: composer)
    let above = context.frame.maxY - glyph.maxY
    let below = glyph.minY - surface.frame.maxY
    XCTAssertEqual(above, below, accuracy: 1, "center the actual AppKit glyph in the visible material, after accounting for glass overlap")
  }

  func testSoftWrappedDraftGrowsAndShrinksWithoutChangingItsText() throws {
    let composer = MacComposerView()
    composer.translatesAutoresizingMaskIntoConstraints = false
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let root = NSView()
    window.contentView = root
    root.addSubview(composer)
    let width = composer.widthAnchor.constraint(equalToConstant: 400)
    NSLayoutConstraint.activate([
      composer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      composer.topAnchor.constraint(equalTo: root.topAnchor), width,
    ])
    var model = MacComposerModel(mode: .reply)
    composer.render(model, reply: ("lody-ios", "main", "Mac Studio"))
    root.layoutSubtreeIfNeeded()
    let scroll = try XCTUnwrap(composer.input.enclosingScrollView)
    let emptyHeight = scroll.frame.height
    let draft = String(repeating: "Keep the native controls and align the sidebar rows. ", count: 8)
    composer.input.string = draft
    model.text = draft
    composer.render(model, reply: ("lody-ios", "main", "Mac Studio"))
    root.layoutSubtreeIfNeeded()
    let narrowHeight = scroll.frame.height
    XCTAssertGreaterThan(narrowHeight, emptyHeight + 20, "wrapping must grow the editor even without explicit newlines")
    width.constant = 680
    root.layoutSubtreeIfNeeded()
    window.layoutIfNeeded()
    let resized = expectation(description: "native text layout settles after resizing")
    Task { @MainActor in
      while scroll.frame.height >= narrowHeight {
        root.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(10))
      }
      resized.fulfill()
    }
    wait(for: [resized], timeout: 2)
    XCTAssertLessThan(scroll.frame.height, narrowHeight, "a wider editor needs fewer wrapped lines")
    XCTAssertEqual(composer.input.string, draft)
    composer.input.string = ""
    model.text = ""
    composer.render(model, reply: ("lody-ios", "main", "Mac Studio"))
    root.layoutSubtreeIfNeeded()
    window.layoutIfNeeded()
    XCTAssertEqual(scroll.frame.height, emptyHeight, accuracy: 1)
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

  func testACancelledOptionsFailureCannotInvalidateTheNewSelection() throws {
    var pending: [String: CheckedContinuation<CreationOptions, Error>] = [:]
    var completed: Set<String> = []
    let service = MacComposerService(options: { _, id in
      let id = id ?? ""
      defer { completed.insert(id) }
      return try await withCheckedThrowingContinuation { pending[id] = $0 }
    }, create: { _, _ in })
    var model = MacComposerModel(mode: .newSession)
    model.form = CreateSessionForm(userId: "u", workspaceId: "w", projects: [
      CreateProject(id: "p1", machineId: "m1", name: "First"), CreateProject(id: "p2", machineId: "m1", name: "Second"),
    ])
    model.form.open(projectId: "p1", context: nil)
    let controller = MacComposerController(model: model, service: service)
    _ = controller.view
    wait { pending["p1"] != nil }
    controller.selectProject("p2")
    wait { pending["p2"] != nil }
    let second = try XCTUnwrap(pending.removeValue(forKey: "p2"))
    second.resume(returning: CreationOptions(sessionId: "second", agents: [], capabilities: []))
    wait { completed.contains("p2") }
    XCTAssertFalse(controller.model.form.current.failed)
    let first = try XCTUnwrap(pending.removeValue(forKey: "p1"))
    first.resume(throwing: OutboxError.scopeExpired)
    wait { completed.contains("p1") }
    XCTAssertFalse(controller.model.form.current.failed, "a cancelled request must not poison the newer selection")
    XCTAssertEqual(controller.model.form.current.options?.sessionId, "second")
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

@MainActor
final class MacComposerOptionsTests: XCTestCase {
  func testModelSummaryReadsAsTwoAdjacentNativeTextLines() throws {
    let panel = MacComposerOptionsController()
    var model = MacComposerModel(mode: .reply)
    model.replyChoice = ModelChoice(modelId: "a", effort: "high")
    model.replyCapability = Capability(machineId: "m", cliType: "builtin", agentType: "codex",
      models: [CapabilityChoice(id: "a", name: "Model A")], reasoningEfforts: ["a": ["high"]])
    panel.render(model)
    panel.view.setFrameSize(panel.preferredContentSize)
    panel.viewDidLayout()
    let effort = try XCTUnwrap(panel.view.descendants(NSTextField.self).first { $0.stringValue == "High" })
    let heading = try XCTUnwrap(panel.view.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "composer-model-list" })
    let lineHeight = max(effort.fittingSize.height, heading.fittingSize.height)
    XCTAssertLessThanOrEqual(effort.frame.midY - heading.frame.midY, lineHeight + 4,
      "the current effort and model must read as adjacent text lines, rather than separate tall rows")
  }

  func testReplyStateAppliesFastAndModelDefaultsInOneChange() throws {
    let capability = Capability(machineId: "m", cliType: "builtin", agentType: "codex", configOptions: [
      ConfigOption(id: "fast", name: "Fast", type: "boolean", currentValue: .bool(false)),
    ])
    let state = SessionComposerModel(choice: ModelChoice(modelId: "a", effort: "high", modeId: "ask", configOptionValues: [
      "fast": .bool(true), "verbosity": .string("detailed"),
    ]), service: SessionComposerService(options: { _, _ in
      CreationOptions(sessionId: "s", agents: [], capabilities: [capability])
    }, tier: { _, _ in nil }))
    let loaded = expectation(description: "capability loaded")
    state.changed = { loaded.fulfill() }
    state.load(workspaceId: "w", projectId: "p", session: SessionItem(id: "s", title: "S", machineId: "m", cliType: "builtin", agentType: "codex"))
    wait(for: [loaded], timeout: 2)
    var notifications = 0
    state.changed = { notifications += 1 }
    state.change(["fast": false])
    XCTAssertEqual(state.active.modelId, "a", "Fast alone preserves the explicit model")
    XCTAssertEqual(state.active.effort, "high")
    state.change(["fast": true])
    notifications = 0
    state.change(["modelId": "", "effort": "", "fast": false])
    XCTAssertNil(state.active.modelId, "one reset must clear the explicit model as well as Fast")
    XCTAssertNil(state.active.effort)
    XCTAssertEqual(CreateLogic.fastMode(state.capability, state.active)?.enabled, false)
    XCTAssertEqual(state.active.modeId, "ask")
    XCTAssertEqual(state.active.configOptionValues?["verbosity"], .string("detailed"))
    XCTAssertEqual(notifications, 1, "the combined change is published atomically")
  }

  func testEffortTitleRemainsReadableOnCapturedPopoverBackdrops() throws {
    for (name, background) in [(NSAppearance.Name.aqua, 0.92), (.darkAqua, 0.38)] {
      let appearance = try XCTUnwrap(NSAppearance(named: name))
      let panel = MacComposerOptionsController()
      var model = MacComposerModel(mode: .reply)
      model.replyChoice = ModelChoice(effort: "medium")
      var resolved: NSColor?
      appearance.performAsCurrentDrawingAppearance {
        panel.render(model)
        resolved = panel.view.descendants(NSTextField.self).first { $0.stringValue == "Medium" }?.textColor?.usingColorSpace(.deviceRGB)
      }
      let color = try XCTUnwrap(resolved)
      func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
      let alpha = Double(color.alphaComponent)
      let rgb = [color.redComponent, color.greenComponent, color.blueComponent].map { Double($0) * alpha + background * (1 - alpha) }
      let foreground = linear(rgb[0]) * 0.2126 + linear(rgb[1]) * 0.7152 + linear(rgb[2]) * 0.0722
      let backdrop = linear(background)
      let contrast = (max(foreground, backdrop) + 0.05) / (min(foreground, backdrop) + 0.05)
      XCTAssertGreaterThanOrEqual(contrast, 4.5, "current effort must be readable over the real light/dark popover backdrop range")
    }
  }

  func testEchoedDefaultFastValueDoesNotLeaveResetEnabled() throws {
    let panel = MacComposerOptionsController()
    var model = MacComposerModel(mode: .reply)
    model.replyCapability = Capability(machineId: "m", cliType: "builtin", agentType: "codex", configOptions: [
      ConfigOption(id: "fast", name: "Fast", type: "boolean", currentValue: .bool(false)),
    ])
    model.replyChoice = ModelChoice(modelId: "", effort: "", configOptionValues: ["fast": .bool(false)])
    panel.render(model)
    let reset = try XCTUnwrap(panel.view.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "composer-options-reset" })
    XCTAssertFalse(reset.isEnabled, "reply projections store the effective Fast value, including the agent default")
  }

  func testUnchangedProjectionPreservesAKeyboardBrowsedModelUntilConfirmation() throws {
    let choices = MacModelChoicesView()
    let models = [CapabilityChoice(id: "a", name: "A"), CapabilityChoice(id: "b", name: "B")]
    choices.render(models: models, selectedId: "a")
    let table = try XCTUnwrap(choices.documentView as? NSTableView)
    table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
    choices.render(models: models, selectedId: "a")
    XCTAssertEqual(table.selectedRow, 2, "an unchanged live projection must not reset keyboard browsing")
    choices.render(models: [models[0]], selectedId: "a")
    XCTAssertEqual(table.selectedRow, 1, "a capability change drops a pending choice that is no longer offered")
  }

  func testResetRestoresAgentDefaultsWithoutChangingPermissionOrOtherOptions() throws {
    let panel = MacComposerOptionsController()
    var model = MacComposerModel(mode: .reply)
    model.replyCapability = Capability(machineId: "m", cliType: "builtin", agentType: "codex",
      models: [CapabilityChoice(id: "a", name: "A")], reasoningEfforts: ["a": ["high"]],
      configOptions: [ConfigOption(id: "fast", name: "Fast", type: "boolean", currentValue: .bool(false))])
    model.replyChoice = ModelChoice(modelId: "a", effort: "high", modeId: "ask", configOptionValues: [
      "fast": .bool(true), "verbosity": .string("detailed"),
    ])
    var changed: ModelChoice?
    panel.onChange = { changed = $0 }
    panel.render(model)
    let reset = try XCTUnwrap(panel.view.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "composer-options-reset" }, "the production panel needs its native reset action")
    reset.performClick(nil)
    let defaults = try XCTUnwrap(changed)
    XCTAssertEqual(defaults.modelId, "")
    XCTAssertEqual(defaults.effort, "")
    XCTAssertEqual(defaults.modeId, "ask")
    XCTAssertEqual(defaults.configOptionValues?["verbosity"], .string("detailed"))
    XCTAssertNil(defaults.configOptionValues?["fast"], "reset removes the Fast override instead of pinning another override")
    XCTAssertEqual(CreateLogic.fastMode(model.capability, defaults)?.enabled, false)
    model.replyChoice = defaults
    panel.render(model)
    XCTAssertFalse(reset.isEnabled, "a second reset would have no effect")
  }

  func testResetUsesAnEnabledAgentFastDefault() throws {
    let panel = MacComposerOptionsController()
    var model = MacComposerModel(mode: .reply)
    model.replyCapability = Capability(machineId: "m", cliType: "builtin", agentType: "codex", configOptions: [
      ConfigOption(id: "fast-mode", name: "Fast", type: "boolean", currentValue: .bool(true)),
    ])
    model.replyChoice = ModelChoice(configOptionValues: ["fast-mode": .bool(false)])
    var changed: ModelChoice?
    panel.onChange = { changed = $0 }
    panel.render(model)
    let reset = try XCTUnwrap(panel.view.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "composer-options-reset" })
    reset.performClick(nil)
    XCTAssertEqual(CreateLogic.fastMode(model.capability, try XCTUnwrap(changed))?.enabled, true)
  }

  func testChangingModelsResetsEffortAndReplacesItsAvailableStops() throws {
    let panel = MacComposerOptionsController()
    var model = MacComposerModel(mode: .reply)
    model.replyCapability = Capability(machineId: "m", cliType: "builtin", agentType: "claude", models: [
      CapabilityChoice(id: "a", name: "Opus"), CapabilityChoice(id: "b", name: "Sonnet"),
    ], reasoningEfforts: ["a": ["ultra", "high", "low"], "b": ["medium", "low"]])
    model.replyChoice = ModelChoice(modelId: "a", effort: "ultra")
    var changed: ModelChoice?
    panel.onChange = { changed = $0 }
    panel.render(model)
    panel.selectModel("b")
    XCTAssertEqual(changed?.modelId, "b")
    XCTAssertEqual(changed?.effort, "", "an old model's effort must not leak into the new model")
    model.replyChoice = try XCTUnwrap(changed)
    panel.render(model)
    panel.slider.doubleValue = 1
    panel.changeEffort()
    XCTAssertEqual(changed?.effort, "medium", "the full end is the highest supported effort regardless of server ordering")
    model.replyChoice = try XCTUnwrap(changed)
    panel.render(model)
    panel.slider.doubleValue = 0
    panel.changeEffort()
    XCTAssertEqual(changed?.effort, "", "Default stays distinct from explicit efforts")
  }

  func testFastOnlyEmitsWhenTheCapabilitySupportsIt() {
    let panel = MacComposerOptionsController()
    var model = MacComposerModel(mode: .reply)
    var picked: Bool?
    panel.onFast = { picked = $0 }
    panel.render(model)
    panel.toggleFast()
    XCTAssertNil(picked)
    model.replyCapability = Capability(machineId: "m", cliType: "builtin", agentType: "claude", configOptions: [ConfigOption(id: "fast-mode", name: "Fast", type: "boolean", currentValue: .bool(false))])
    panel.render(model)
    panel.toggleFast()
    XCTAssertEqual(picked, true)
    XCTAssertFalse(panel.fast.isHidden)
    model.replyChoice = CreateLogic.withFastMode(model.capability, model.choice, enabled: true)
    panel.render(model)
    XCTAssertEqual(panel.fast.state, .on)
  }

  func testReplacingCapabilitiesHidesUnsupportedEffortAndRejectsStaleModelChoices() {
    let panel = MacComposerOptionsController()
    var model = MacComposerModel(mode: .reply)
    model.replyCapability = Capability(machineId: "m", cliType: "builtin", agentType: "codex", models: [CapabilityChoice(id: "gpt", name: "GPT")], reasoningEfforts: ["gpt": ["high", "low"]])
    model.replyChoice = ModelChoice(modelId: "gpt", effort: "high")
    panel.render(model)
    XCTAssertFalse(panel.slider.isHidden)
    var changes = 0
    panel.onChange = { _ in changes += 1 }
    model.replyCapability = nil
    panel.render(model)
    XCTAssertTrue(panel.slider.isHidden)
    panel.selectModel("gpt")
    panel.changeEffort()
    XCTAssertEqual(changes, 0, "a panel kept open during a capability change cannot send unavailable choices")
  }
}

@MainActor
final class MacInterruptionStudyTests: XCTestCase {
  func testAnOptionIsClickableAcrossItsAvailableRowWidth() throws {
    var chosen = false
    let row = MacInterruptionOption(title: "macOS", detail: "Run the native Mac checks", index: 0, action: { chosen = true })
    row.frame = NSRect(x: 0, y: 0, width: 600, height: 52)
    row.layoutSubtreeIfNeeded()
    let hit = row.hitTest(NSPoint(x: 480, y: 26))
    let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 480, y: 26), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    hit?.mouseDown(with: event)
    XCTAssertTrue(chosen, "clicking the label side of the row must choose its native control")
  }

  func testNativeChoiceCenterIsAnInteractiveRadioTarget() throws {
    let study = MacInterruptionStudy(content: .questions)
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let root = NSView()
    window.contentView = root
    study.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(study)
    NSLayoutConstraint.activate([
      study.widthAnchor.constraint(equalToConstant: 748),
      study.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      study.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    root.layoutSubtreeIfNeeded()
    window.layoutIfNeeded()
    root.layoutSubtreeIfNeeded()
    let option = try XCTUnwrap(study.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "question-option-0" })
    let center = NSPoint(x: option.bounds.midX, y: option.bounds.midY)
    XCTAssertTrue(root.hitTest(option.convert(center, to: root)) === option, "the native option must not be covered by its row container")
    let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: option.convert(center, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    let hit = try XCTUnwrap(option.cell).hitTest(for: event, in: option.bounds, of: option)
    XCTAssertTrue(hit.contains(.trackableArea), "the center must land on native radio content, rather than empty stretched bounds")
    option.performClick(nil)
    let next = try XCTUnwrap(study.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "question-next" })
    XCTAssertTrue(next.isEnabled)
  }
}
