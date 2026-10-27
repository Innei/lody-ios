import UIKit

extension SessionController {
  func prepareSimulator(_ state: SessionListState, _ session: SessionItem) {
    guard simulator == nil, state.catalog.machineSimulators[session.machineId] != nil else { return }
    let store = SessionSimulator(sessionId: sessionId,
      service: simulatorService ?? .live(workspaceId: state.workspaceId, userId: state.userId, sessionId: sessionId))
    simulator = store
    store.watch(self) { [weak self, weak store] in
      guard let self, let store else { return }
      chat.setSimulatorPreview(store.previewJSON)
      renderComposer()
      render()
    }
    chat.onPreview.onEventSent = { [weak self] body in
      guard let self, let action = body["action"] as? String else { return }
      switch action {
      case "close": store.hidePreview()
      case "stop": Task { do { try await store.stop() } catch { self.toolError(error) } }
      case "open", "expand": openSimulator()
      default: break
      }
    }
  }

  var simulatorChip: [String: Any]? {
    guard let session = source.state.catalog.session(sessionId),
      source.state.catalog.machineSimulators[session.machineId] == "available", let simulator,
      session.iosSimulatorPreviewRequestId != nil || simulator.running else { return nil }
    let name = simulator.running ? simulator.name : LodyStrings.text("simulator.menu")
    var chip: [String: Any] = ["label": name, "symbol": "iphone", "state": simulator.connecting ? "connecting" : "ready",
      "accessibilityLabel": LodyStrings.text("simulator.chip.open", ["target": name])]
    chip["actions"] = simulator.running ? [["id": "stop", "title": LodyStrings.text("simulator.stop"), "symbol": "stop.circle", "destructive": true]] : []
    return chip
  }

  func simulatorMenu() -> [UIMenuElement] {
    guard let session = source.state.catalog.session(sessionId),
      let availability = source.state.catalog.machineSimulators[session.machineId] else { return [] }
    let action = UIAction(title: LodyStrings.text("simulator.menu"), image: UIImage(systemName: "iphone")) { [weak self] _ in self?.openSimulator() }
    if availability == "upgrade-required" { action.subtitle = LodyStrings.text("simulator.upgradeRequired") }
    else if let simulator, simulator.running { action.subtitle = simulator.phaseText + " · " + simulator.name }
    return [action]
  }

  func openSimulator() {
    guard !openingSimulator, let session = source.state.catalog.session(sessionId), let simulator else { return }
    if source.state.catalog.machineSimulators[session.machineId] == "upgrade-required" {
      let alert = UIAlertController(title: LodyStrings.text("simulator.menu"), message: LodyStrings.text("simulator.upgradeRequired"), preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: LodyStrings.text("common.ok"), style: .default)); present(alert, animated: true); return
    }
    openingSimulator = true
    Task { [weak self] in
      guard let self else { return }
      defer { openingSimulator = false }
      do {
        simulator.revealPreview()
        if simulator.running { showSimulator(); return }
        if try await simulator.resume() { showSimulator(); return }
        let picker = SimulatorPickerController(store: simulator) { [weak self] device in
          simulator.start(device); self?.showSimulator()
        }
        LodyShell.shared.presentNative(picker, title: LodyStrings.text("simulator.choose"), grabber: true)
      } catch { toolError(error) }
    }
  }
  private func showSimulator() {
    guard let simulator else { return }
    LodyShell.shared.pushNative(SimulatorController(store: simulator), title: simulator.name, from: self)
  }
  private func toolError(_ error: Error) { LodyToastOverlay.shared.show(message: error.localizedDescription, kind: "error") }

  func pullRequestItem(_ session: SessionItem) -> UIBarButtonItem? {
    let references = session.pullRequests
    guard !references.isEmpty else { return nil }
    let item: UIBarButtonItem
    if references.count == 1 {
      let reference = references[0]
      item = UIBarButtonItem(title: "PR #\(reference.number)", primaryAction: UIAction { [weak self] _ in self?.openPullRequest(reference) })
    } else {
      item = UIBarButtonItem(title: "PR · \(references.count)", menu: UIMenu(children: references.map { reference in
        UIAction(title: "\(reference.repository) #\(reference.number) · \(LodyStrings.text("pr.state." + reference.status))") { [weak self] _ in self?.openPullRequest(reference) }
      }))
      item.accessibilityLabel = LodyStrings.text("pr.pullRequests")
    }
    item.tintColor = references.contains { ["f", "e"].contains($0.ci ?? "") } ? .systemOrange : .systemBlue
    return item
  }
  static func livePullRequest(_ reference: SessionPullRequest, _ state: SessionListState) -> PullRequestController {
    let scope = SettingsActor.live(["workspaceId": state.workspaceId, "userId": state.userId])
    let store = PullRequestStore(repository: reference.repository, number: reference.number, scope: scope,
      service: .live(workspaceId: state.workspaceId, repository: reference.repository, number: reference.number))
    return PullRequestController(store: store)
  }

  private func openPullRequest(_ reference: SessionPullRequest) {
    let state = source.state
    let page = pullRequestPage(reference, state)
    page.investigate = { [weak self] text in
      guard let self, source.state.key == state.key else { throw OutboxError.scopeExpired }
      chat.composer.appendDraft(Self.json(["id": UUID().uuidString, "text": text]))
    }
    LodyShell.shared.pushNative(page, title: "PR #\(reference.number)", from: self)
  }

  func updateDetails(_ json: String) { subagentPage?.update(json) }
}
