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
  private let control: SessionControl
  private var feed = SessionFeedState()
  private var pending = ""
  private var observers: [NSObjectProtocol] = []
  private let queuedBehavior: @MainActor () -> String
  var onPending: (() -> Void)?

  var pendingJSON: String { sender.pendingSendJSON }

  init(sessionId: String, sessions: MacSessionsSource, controlRequest: @escaping SessionControl.Request = SessionControl.live, sender injectedSender: SessionSender? = nil,
       composerService: SessionComposerService = .live, queuedBehavior: @escaping @MainActor () -> String = { LodyPreferences.queuedMessageBehavior }) {
    self.sessionId = sessionId
    self.sessions = sessions
    control = SessionControl(request: controlRequest)
    self.queuedBehavior = queuedBehavior
    let state = sessions.read()
    let sender = injectedSender ?? SessionSender(
      sessionId: sessionId, store: OutboxSession.shared.outboxStore(user: state.userId, workspace: state.workspaceId),
      services: OutboxSession.shared.services, inflight: OutboxSession.published.inflight
    )
    let choices = SessionComposerModel(choice: nil, service: composerService)
    self.sender = sender
    self.choices = choices
    composer = MacComposerController(model: MacComposerModel(mode: .reply), service: MacComposerService(
      options: { _, _ in throw OutboxError.scopeExpired },
      create: { _, _ in },
      reply: { [weak sender, weak choices] payload, _ in sender?.submit(payload, choice: choices?.sendChoice ?? [:]) }
    ))
    composer.bindDraft(.init(user: state.userId, workspace: state.workspaceId, session: sessionId))
    composer.onReplyChoice = { [weak self] body in
      self?.choices.change(body)
      self?.refresh()
    }
    sender.changed = { [weak self] in self?.refresh() }
    sender.restoreDraft = { [weak composer] _ in composer?.restoreDraft() }
    sender.clearDraft = { [weak composer] _ in composer?.clearDraft() }
    choices.changed = { [weak self] in self?.refresh() }
    control.changed = { [weak self] in self?.refresh() }
    composer.onStop = { [weak self] in self?.controlTurn("stop") }
    observers = [.lodyCatalogDidChange, .lodyPreferencesDidChange].map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
    }
  }

  isolated deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
  }

  func retry() { sender.retry() }

  func controlTurn(_ action: String, messageId: String? = nil) {
    guard let session = sessions.read().catalog.session(sessionId) else { return }
    control.act(action, messageId: messageId, session: session, transcript: feed.transcript,
                live: feed.status == "live", overflow: feed.overflow, steerable: choices.steerable)
  }

  func setStreaming(_ on: Bool) {
    if on { OutboxSession.shared.setForeground(sessionId) } else { OutboxSession.shared.leaveForeground(sessionId) }
  }

  func update(_ next: SessionFeedState) {
    feed = next
    let entries = (try? JSONSerialization.jsonObject(with: Data(next.entriesJSON.utf8))) as? [[String: Any]] ?? []
    composer.updateQueueCount(entries.filter { $0["status"] as? String == "queued" }.count)
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
      steerable: choices.steerable, promptBusy: OutboxDispatcher.busy.contains(session.status), queuedMessageBehavior: queuedBehavior(), transcript: feed.transcript
    )
    let inputs = SessionSender.Inputs(userId: state.userId, connected: state.connected && !state.loading, session: session, context: context)
    if sender.inputs != inputs { sender.update(inputs) }
    composer.replyContext = (project?.name ?? "", session.branchName ?? "", state.catalog.machineNames[session.machineId] ?? "")
    composer.updateReply(ready: sender.canSend, capability: choices.capability, choice: choices.active)
    composer.updateRun(control.state(session: session, transcript: feed.transcript, live: live, overflow: feed.overflow, steerable: choices.steerable))
    composer.reconcileDraft(pending: sender.record?.sendId, delivered: feed.transcript.entryIds,
                            uploaded: sender.record.map { ["accepted", "uploaded", "queued"].contains($0.phase) } ?? false)
    let next = sender.pendingSendJSON
    if next != pending {
      pending = next
      onPending?()
    }
  }
}
