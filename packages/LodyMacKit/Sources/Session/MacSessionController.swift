import AppKit
import LodyCore
import LodyData

@MainActor
struct MacTranscriptSource {
  var start: @MainActor (_ changed: @escaping @MainActor (SessionFeedState) -> Void) -> Void
  var stop: @MainActor () -> Void
  var detail: MacPermissionFlow.Detail
  var respond: MacPermissionFlow.Respond

  static func live(sessionId: String, state: SessionListState, permission: PermissionService = .live) -> MacTranscriptSource {
    let feed = SessionFeed(sessionId: sessionId, userId: state.userId, workspaceId: state.workspaceId)
    return MacTranscriptSource(
      start: { [feed] changed in
        feed.changed = { [weak feed] in if let feed { changed(feed.state) } }
        feed.start()
      },
      stop: { feed.finish() },
      detail: { target in
        try await permission.detail(sessionId, target).options?.map { .init(optionId: $0.optionId, name: $0.name, kind: $0.kind) }
      },
      respond: { target, optionId in
        try await permission.respond(.init(
          sessionId: sessionId, entryId: target.entryId, itemId: target.itemId,
          requestId: target.requestId, optionId: optionId
        ))
      }
    )
  }
}

@MainActor
final class MacSessionController: NSViewController, MacSessionPane {
  let sessionId: String
  private let source: MacTranscriptSource
  private let transcript = MacTranscriptView()
  private let composer: NSViewController?
  private let permission: MacPermissionFlow
  private var model = MacTranscriptModel(entriesJSON: "[]")
  private var parsed = MacTranscriptModel.Parsed("[]")
  private var feed = SessionFeedState()
  private var streaming = false

  init(sessionId: String, source: MacTranscriptSource, composer: NSViewController? = nil) {
    self.sessionId = sessionId
    self.source = source
    self.composer = composer
    permission = MacPermissionFlow(detail: source.detail, respond: source.respond)
    super.init(nibName: nil, bundle: nil)
    permission.changed = { [weak self] in self?.paint() }
  }

  required init?(coder: NSCoder) { nil }

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 620))
    transcript.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(transcript)
    var constraints = [
      transcript.topAnchor.constraint(equalTo: root.topAnchor),
      transcript.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      transcript.trailingAnchor.constraint(equalTo: root.trailingAnchor),
    ]
    if let composer {
      addChild(composer)
      composer.view.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(composer.view)
      constraints += [
        transcript.bottomAnchor.constraint(equalTo: composer.view.topAnchor),
        composer.view.centerXAnchor.constraint(equalTo: root.centerXAnchor),
        composer.view.widthAnchor.constraint(lessThanOrEqualToConstant: 780),
        composer.view.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -32).withPriority(.defaultHigh),
        composer.view.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
      ]
    } else {
      constraints.append(transcript.bottomAnchor.constraint(equalTo: root.bottomAnchor))
    }
    NSLayoutConstraint.activate(constraints)
    transcript.onAnswer = { [weak self] optionId in self?.permission.answer(optionId) }
    transcript.onRetry = { [weak self] in self?.onRetry?() }
    view = root
  }

  func setStreaming(_ on: Bool) {
    guard on != streaming else { return }
    streaming = on
    onStreaming?(on)
    if on {
      source.start { [weak self] state in self?.render(state) }
    } else {
      source.stop()
    }
  }

  var onFeed: ((SessionFeedState) -> Void)?
  var onStreaming: ((Bool) -> Void)?
  var onRetry: (() -> Void)?
  var pendingJSON: () -> String = { "" }
  var retained: AnyObject?

  func refreshPending() {
    guard isViewLoaded else { return }
    rebuild()
  }

  private func render(_ state: SessionFeedState) {
    feed = state
    rebuild()
    onFeed?(state)
  }

  private func rebuild() {
    if parsed.json != feed.entriesJSON { parsed = MacTranscriptModel.Parsed(feed.entriesJSON) }
    model = MacTranscriptModel(parsed: parsed, pendingJSON: pendingJSON())
    permission.show(model.permission)
    paint()
  }

  private func paint() {
    guard isViewLoaded else { return }
    transcript.render(model, card: permission.card)
  }
}
