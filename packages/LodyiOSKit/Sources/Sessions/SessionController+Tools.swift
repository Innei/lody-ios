import LodyCore
import SafariServices
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

  }

  var simulatorChip: [String: Any]? {
    guard let session = source.state.catalog.session(sessionId),
      source.state.catalog.machineSimulators[session.machineId] == "available", let simulator,
      session.iosSimulatorPreviewRequestId != nil || simulator.running else { return nil }
    let name = simulator.running ? simulator.name : String(localized: "simulator.menu", bundle: .lody)
    var chip: [String: Any] = ["label": name, "symbol": "iphone", "state": simulator.connecting ? "connecting" : "ready",
      "accessibilityLabel": String.localizedStringWithFormat(String(localized: "simulator.chip.open", bundle: .lody), String(describing: name))]
    chip["actions"] = simulator.running ? [["id": "stop", "title": String(localized: "simulator.stop", bundle: .lody), "symbol": "stop.circle", "destructive": true]] : []
    return chip
  }

  func simulatorMenu() -> [UIMenuElement] {
    guard let session = source.state.catalog.session(sessionId),
      let availability = source.state.catalog.machineSimulators[session.machineId] else { return [] }
    let action = UIAction(title: String(localized: "simulator.menu", bundle: .lody), image: UIImage(systemName: "iphone")) { [weak self] _ in self?.openSimulator() }
    if availability == "upgrade-required" { action.subtitle = String(localized: "simulator.upgradeRequired", bundle: .lody) }
    else if let simulator, simulator.running { action.subtitle = simulator.phaseText + " · " + simulator.name }
    return [action]
  }

  func openSimulator() {
    guard !openingSimulator, let session = source.state.catalog.session(sessionId), let simulator else { return }
    if source.state.catalog.machineSimulators[session.machineId] == "upgrade-required" {
      let alert = UIAlertController(title: String(localized: "simulator.menu", bundle: .lody), message: String(localized: "simulator.upgradeRequired", bundle: .lody), preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: String(localized: "common.ok", bundle: .lody), style: .default)); present(alert, animated: true); return
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
        LodyShell.shared.presentNative(picker, title: String(localized: "simulator.choose", bundle: .lody), grabber: true)
      } catch { toolError(error) }
    }
  }
  private func showSimulator() {
    guard let simulator else { return }
    LodyShell.shared.pushNative(SimulatorController(store: simulator), title: simulator.name, from: self)
  }
  private func toolError(_ error: Error) { LodyToastOverlay.shared.show(message: error.localizedDescription, kind: "error") }

  static func ciFailing(_ reference: SessionPullRequest) -> Bool {
    ["f", "e"].contains(reference.ci ?? "")
  }

  static func pullRequestCaption(_ references: [SessionPullRequest]) -> (label: String, failing: Bool) {
    guard let first = references.first else { return ("", false) }
    let label = references.count > 1 ? "#\(first.number) +\(references.count - 1)" : "#\(first.number)"
    return (label, references.contains(where: ciFailing))
  }

  static func livePullRequest(_ reference: SessionPullRequest, _ state: SessionListState) -> PullRequestController {
    let scope = SettingsActor.live(["workspaceId": state.workspaceId, "userId": state.userId])
    let store = PullRequestStore(repository: reference.repository, number: reference.number, scope: scope,
      service: .live(workspaceId: state.workspaceId, repository: reference.repository, number: reference.number))
    return PullRequestController(store: store)
  }

  func openPullRequest(_ reference: SessionPullRequest) {
    let state = source.state
    let page = pullRequestPage(reference, state)
    page.investigate = { [weak self] text in
      guard let self, source.state.key == state.key else { throw OutboxError.scopeExpired }
      chat.composer.appendDraft(Self.json(["id": UUID().uuidString, "text": text]))
    }
    LodyShell.shared.presentDetail(page, title: "PR #\(reference.number)", from: self, push: true)
  }

  func updateDetails(_ json: String) { subagentPage?.update(json) }

}

extension SessionController {
  var browserChip: [String: Any]? {
    guard let preview = feed?.state.preview else { return nil }
    var actions: [[String: Any]] = [["id": "copy", "title": String(localized: "session.preview.copyLink", bundle: .lody), "symbol": "link"]]
    if preview.active { actions.append(["id": "stop", "title": String(localized: "session.preview.stop", bundle: .lody), "symbol": "stop.circle", "destructive": true]) }
    return ["label": browserBusy ? String(localized: "session.preview.connecting", bundle: .lody) : preview.label,
      "symbol": "safari", "state": browserBusy ? "connecting" : "ready",
      "accessibilityLabel": String.localizedStringWithFormat(String(localized: "session.preview.open", bundle: .lody), String(describing: preview.label)), "actions": actions]
  }

  var contextChips: [(id: String, chip: [String: Any])] {
    var chips: [(String, [String: Any])] = []
    if let browserChip { chips.append(("browser", browserChip)) }
    if let simulatorChip { chips.append(("simulator", simulatorChip)) }
    return chips
  }

  func makeComposerPreview() -> [String: Any]? {
    let chips = contextChips
    guard chips.count > 1 else { return chips.first?.chip }
    let label = String.localizedStringWithFormat(String(localized: "session.context.count", bundle: .lody), String(describing: chips.count))
    let actions = chips.flatMap { source in
      (source.chip["actions"] as? [[String: Any]] ?? []).map { action in
        var action = action; action["id"] = source.id + ":" + (action["id"] as! String); return action
      }
    }
    return ["label": label, "symbol": "square.stack", "state": browserBusy || simulator?.connecting == true ? "connecting" : "ready",
      "accessibilityLabel": label, "actions": actions]
  }

  func contextAction(_ action: String) {
    // The floating simulator uses these actions independently of the composer chip.
    if action == "expand" { openSimulator(); return }
    if action == "close" { simulator?.hidePreview(); return }
    let chips = contextChips
    if chips.count < 2 { resourceAction(chips.first?.id ?? "simulator", action); return }
    if action != "open", let separator = action.firstIndex(of: ":") {
      resourceAction(String(action[..<separator]), String(action[action.index(after: separator)...])); return
    }
    let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
    for source in chips {
      menu.addAction(UIAlertAction(title: source.chip["accessibilityLabel"] as? String, style: .default) { [weak self] _ in
        self?.resourceAction(source.id, "open")
      })
    }
    menu.addAction(UIAlertAction(title: String(localized: "common.cancel", bundle: .lody), style: .cancel))
    menu.popoverPresentationController?.sourceView = chat.composer
    menu.popoverPresentationController?.sourceRect = chat.composer.bounds
    present(menu, animated: true)
  }

  private func resourceAction(_ resource: String, _ action: String) {
    if resource == "browser" { browserAction(action); return }
    if action == "stop" {
      Task { do { try await simulator?.stop() } catch { toolError(error) } }
    } else { openSimulator() }
  }

  private func browserAction(_ action: String) {
    guard !browserBusy else { return }
    let state = source.state
    browserBusy = true; renderComposer()
    Task { [weak self] in
      guard let self else { return }
      defer { browserBusy = false; renderComposer() }
      do {
        let command: RuntimeContract.SessionPreviewParamsAction = action == "stop" ? .revoke : .create
        let reply = try await requestBrowserPreview(state, command)
        guard source.state.key == state.key else { throw OutboxError.scopeExpired }
        guard viewIfLoaded?.window != nil else { return }
        if let error = reply.error {
          let message = error == "unsupported" ? String(localized: "session.preview.unsupported", bundle: .lody) : reply.message ?? String(localized: "session.preview.generic", bundle: .lody)
          throw SettingsError(message)
        }
        if action == "stop" { LodyToastOverlay.shared.show(message: String(localized: "session.preview.stopped", bundle: .lody), kind: "info"); return }
        guard let address = reply.url, let url = URL(string: address), url.scheme == "https", url.user == nil, url.password == nil,
              url.host?.hasSuffix(".trycloudflare.com") == true else { throw SettingsError(String(localized: "session.preview.generic", bundle: .lody)) }
        if action == "copy" {
          UIPasteboard.general.string = address
          LodyToastOverlay.shared.show(message: String(localized: "session.preview.copied", bundle: .lody), kind: "info")
        } else { present(SFSafariViewController(url: url), animated: true) }
      } catch {
        guard viewIfLoaded?.window != nil else { return }
        let alert = UIAlertController(title: String(localized: "session.preview.failed", bundle: .lody), message: String(describing: error), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "common.ok", bundle: .lody), style: .default)); present(alert, animated: true)
      }
    }
  }
}
