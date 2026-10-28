import LodyCore
import UIKit

@MainActor
struct SessionSendEnvironment {
  var store: @MainActor (_ userId: String, _ workspaceId: String) -> OutboxStore?
  var services: @MainActor () -> OutboxServices
  var inflight: OutboxInflight
  var serverCreated: @MainActor (_ sessionId: String) -> Bool
  var foreground: @MainActor (_ sessionId: String, _ active: Bool) -> Void
  var control: SessionControl.Request
  var composer: SessionComposerService
  var turn: @MainActor (_ payload: String) async throws -> String = { payload in
    guard let runtime = DataRuntime.current else { throw OutboxError.scopeExpired }
    return try await withCheckedThrowingContinuation { runtime.sendTurn(payload, sink: .continuation($0)) }
  }
  var readEdit: @MainActor (_ payload: String) async throws -> String = { payload in
    guard let runtime = DataRuntime.current else { throw OutboxError.scopeExpired }
    return try await withCheckedThrowingContinuation {
      runtime.dispatchTurn(payload, sink: .continuation($0), billing: nil, edit: true)
    }
  }

  static let live = SessionSendEnvironment(
    store: { OutboxSession.shared.outboxStore(user: $0, workspace: $1) },
    services: { OutboxSession.shared.services },
    inflight: OutboxSession.published.inflight,
    serverCreated: { OutboxSession.shared.serverCreated($0) },
    foreground: { id, active in
      if active { OutboxSession.shared.setForeground(id) } else { OutboxSession.shared.leaveForeground(id) }
    },
    control: SessionControl.live,
    composer: .live
  )
}

extension SessionController {
  func startSender(_ state: SessionListState) {
    guard sender == nil else { return }
    let sender = SessionSender(
      sessionId: sessionId, store: environment.store(state.userId, state.workspaceId),
      services: environment.services(), inflight: environment.inflight
    )
    sender.changed = { [weak self] in self?.renderComposer() }
    sender.clearDraft = { [weak self] in self?.chat.clearDraft(token: $0) }
    sender.restoreDraft = { [weak self] in self?.chat.restoreDraft(token: $0) }
    composerModel.changed = { [weak self] in self?.renderComposer() }
    control.changed = { [weak self] in self?.renderComposer() }
    self.sender = sender
    environment.foreground(sessionId, true)
    if persistsDraft { chat.setDraftKey("draft:\(state.userId):\(state.workspaceId):\(sessionId)") }
  }

  func wireSendEvents() {
    chat.onSend = { [weak self] body in
      guard let self, !SessionActions.isDeleting(self.source.state.workspaceId, self.sessionId), !self.planDecision.pending
      else { return }
      self.sender?.submit(body, choice: self.composerModel.sendChoice)
    }
    chat.onRetrySend = { [weak self] _ in self?.sender?.retry() }
    chat.onComposerOptionChange = { [weak self] body in self?.composerModel.change(body) }
    chat.onStop = { [weak self] _ in self?.controlTurn("stop") }
    chat.onSteer = { [weak self] body in self?.controlTurn("steer", messageId: body["id"] as? String) }
  }

  private func controlTurn(_ action: String, messageId: String? = nil) {
    guard let session = source.state.catalog.session(sessionId), let state = feed?.state else { return }
    control.act(
      action, messageId: messageId, session: session, transcript: state.transcript, live: state.status == "live",
      overflow: state.overflow, steerable: composerModel.steerable
    )
  }

  func renderComposer() {
    guard isViewLoaded, let session = source.state.catalog.session(sessionId) else { return }
    renderComposer(session, feed?.state ?? SessionFeedState())
  }

  func renderComposer(_ session: SessionItem, _ feed: SessionFeedState) {
    let state = source.state, live = feed.status == "live"
    composerModel.hydrate(
      pending: sender?.record, ready: sender?.ready == true,
      snapshot: feed.composerJSON.flatMap { CreateJSON.decode(ModelChoice.self, $0) }
    )
    let project = state.catalog.projects.first { $0.id == session.projectId }
    composerModel.load(workspaceId: state.workspaceId, projectId: project?.id, session: session)
    let billable = live ? feed.billableTurnCount : nil
    composerModel.watchTier(workspaceId: state.workspaceId, userId: state.userId, watch: (billable ?? 0) >= 25)
    let locked = SessionQuota.locked(count: billable, tier: composerModel.tier)
    announceQuota(live: live, locked: locked)
    let steerable = composerModel.steerable
    let behavior = queuedMessageBehavior
    let context = OutboxForeground(
      live: live, overflow: feed.overflow, serverCreated: environment.serverCreated(sessionId), steerable: steerable,
      promptBusy: OutboxDispatcher.busy.contains(session.status), queuedMessageBehavior: behavior, transcript: feed.transcript
    )
    let inputs = SessionSender.Inputs(
      userId: state.userId, connected: state.connected && !state.loading, session: session, context: context
    )
    if let sender, sender.inputs != inputs { sender.update(inputs) }
    let control = self.control.state(
      session: session, transcript: feed.transcript, live: live, overflow: feed.overflow, steerable: steerable
    )
    let deleting = SessionActions.isDeleting(state.workspaceId, sessionId)
    var composer: [String: Any] = [
      "editable": !session.archived && !deleting && !locked,
      "canSend": sender?.canSend == true && !deleting && !locked && !planDecision.pending && !errorRetry.pending,
      "sending": sender?.sending == true,
      "running": control.running || sender?.awaitingReply == true,
      "canStop": control.canStop, "stopping": control.stopping, "controlling": control.controlling,
      "steerID": control.steerID, "steerInterrupts": control.steerInterrupts,
      "queuedMessageBehavior": behavior,
      "notice": feed.overflow ? LodyStrings.text("chat.notice.syncStopped") : "",
      "quotaNotice": locked ? "" : quotaNotice(feed.billableTurnCount, live: live),
      "quotaLocked": locked,
      "reconnect": feed.overflow,
      "connection": connection(feed),
      "placeholder": placeholder(session, locked: locked),
    ]
    let replies = live && feed.transcript.conversational ? LodyPreferences.quickReplies : []
    composer["quickReplies"] = replies.map { ["id": $0.id, "label": $0.label, "message": $0.message] }
    composer["preview"] = composerPreview
    adjustComposer(&composer)
    apply("composer", Self.json(composer), chat.setComposerState)
    apply("options", composerModel.optionsJSON, chat.setComposerOptions)
    apply("pending", sender?.pendingSendJSON ?? "", chat.setPendingSendJSON)
    renderDecisions(feed)
    renderEditable(feed, enabled: live && state.connected && !state.loading && !session.archived && sender?.sending != true
      && !control.controlling && !feed.overflow && !deleting && !locked)
  }

  func apply(_ key: String, _ value: String, _ set: (String) -> Void) {
    guard rendered[key] != value else { return }
    rendered[key] = value
    set(value)
  }

  private func connection(_ feed: SessionFeedState) -> String {
    if feed.overflow { return "" }
    if ["offline", "failed", "stopped"].contains(feed.status) { return "paused" }
    return feed.status == "live" ? "" : "connecting"
  }

  private func placeholder(_ session: SessionItem, locked: Bool) -> String {
    if session.archived { return LodyStrings.text("chat.composer.archived") }
    if locked { return "" }
    return LodyStrings.text("chat.composer.placeholder")
  }

  private func quotaNotice(_ count: Int?, live: Bool) -> String {
    guard live, let remaining = SessionQuota.remaining(count: count, tier: composerModel.tier) else { return "" }
    if remaining == 0 { return LodyStrings.text("chat.composer.freeTurnLimit") }
    return LodyStrings.plural("chat.composer.freeTurnsRemaining", remaining)
  }

  private func announceQuota(live: Bool, locked: Bool) {
    guard live, composerModel.tier != nil, quotaEntry == "pending" else { return }
    quotaEntry = locked ? "closed" : "open"
    guard locked else { return }
    let alert = UIAlertController(
      title: LodyStrings.text("chat.composer.freeTurnLimitTitle"),
      message: LodyStrings.text("chat.composer.freeTurnLimitBody"), preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: LodyStrings.text("common.ok"), style: .default))
    present(alert, animated: true)
  }
}
