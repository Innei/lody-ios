import AppKit
import LodyCore
import LodyData

@MainActor
final class MacReplyBridge {
  let composer: MacComposerController
  private let sessionId: String
  private let sessions: MacSessionsSource
  private let sender: SessionSender
  private let choices: SessionComposerModel
  private var feed = SessionFeedState()
  private var pending = ""
  private var observer: NSObjectProtocol?
  var onPending: (() -> Void)?

  var pendingJSON: String { sender.pendingSendJSON }

  init(sessionId: String, sessions: MacSessionsSource) {
    self.sessionId = sessionId
    self.sessions = sessions
    let state = sessions.read()
    let sender = SessionSender(
      sessionId: sessionId, store: OutboxSession.shared.outboxStore(user: state.userId, workspace: state.workspaceId),
      services: OutboxSession.shared.services, inflight: OutboxSession.published.inflight
    )
    let choices = SessionComposerModel(choice: nil)
    self.sender = sender
    self.choices = choices
    composer = MacComposerController(model: MacComposerModel(mode: .reply), service: MacComposerService(
      options: { _, _ in throw OutboxError.scopeExpired },
      create: { _, _ in },
      reply: { [weak sender, weak choices] payload, _ in sender?.submit(payload, choice: choices?.sendChoice ?? [:]) }
    ))
    composer.onReplyChoice = { [weak self] body in
      self?.choices.change(body)
      self?.refresh()
    }
    sender.changed = { [weak self] in self?.refresh() }
    sender.restoreDraft = { [weak composer] _ in composer?.restoreDraft() }
    sender.clearDraft = { [weak composer] _ in composer?.clearDraft() }
    choices.changed = { [weak self] in self?.refresh() }
    observer = NotificationCenter.default.addObserver(forName: .lodyCatalogDidChange, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.refresh() }
    }
  }

  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  func retry() { sender.retry() }

  func setStreaming(_ on: Bool) {
    if on { OutboxSession.shared.setForeground(sessionId) } else { OutboxSession.shared.leaveForeground(sessionId) }
  }

  func update(_ next: SessionFeedState) {
    feed = next
    refresh()
  }

  private func refresh() {
    let state = sessions.read()
    guard let session = state.catalog.session(sessionId) else { return }
    let live = feed.status == "live"
    choices.hydrate(pending: sender.record, ready: sender.ready, snapshot: feed.composerJSON.flatMap { CreateJSON.decode(ModelChoice.self, $0) })
    let project = state.catalog.projects.first { $0.id == session.projectId }
    choices.load(workspaceId: state.workspaceId, projectId: project?.id, session: session)
    let context = OutboxForeground(
      live: live, overflow: feed.overflow, serverCreated: OutboxSession.shared.serverCreated(sessionId),
      steerable: choices.steerable, promptBusy: OutboxDispatcher.busy.contains(session.status), transcript: feed.transcript
    )
    let inputs = SessionSender.Inputs(userId: state.userId, connected: state.connected && !state.loading, session: session, context: context)
    if sender.inputs != inputs { sender.update(inputs) }
    composer.replyContext = (project?.name ?? "", session.branchName ?? "", state.catalog.machineNames[session.machineId] ?? "")
    composer.updateReply(ready: sender.canSend, capability: choices.capability, choice: choices.active)
    let next = sender.pendingSendJSON
    if next != pending {
      pending = next
      onPending?()
    }
  }
}
