import AppKit
import ChatKitCore
import LodyCore
import LodyData

@MainActor
final class MacSessionController: NSViewController, MacSessionPane {
  let sessionId: String
  private let source: MacTranscriptSource
  private let transcript = MacTranscriptView()
  private let composer: NSViewController?
  private let permission: MacPermissionFlow
  private var interruption: MacPermissionCard?
  private var restoreInputFocus = false
  private var model = MacTranscriptModel(entriesJSON: "[]")
  private var parsed = MacTranscriptModel.Parsed("[]")
  private var feed = SessionFeedState()
  private var streaming = false
  private var composerWidths: [NSLayoutConstraint] = []
  private var readingObserver: NSObjectProtocol?
  private weak var queuePage: MacQueueController?
  private weak var diffPage: MacDiffController?
  var onSteer: ((String) -> Void)?
  var previewURL: URL?
  var transcriptMedia: CKMediaProvider? { source.media }
  func focusTranscript() { transcript.focus() }

  var reading = MacReading.current() {
    didSet {
      transcript.reading = reading
      composerWidths.forEach { $0.constant = reading.columnWidth }
    }
  }

  init(sessionId: String, source: MacTranscriptSource, composer: NSViewController? = nil) {
    self.sessionId = sessionId
    self.source = source
    self.composer = composer
    permission = MacPermissionFlow(detail: source.detail, respond: source.respond, respondQuestions: source.respondQuestions)
    super.init(nibName: nil, bundle: nil)
    permission.changed = { [weak self] in self?.paint() }
    readingObserver = NotificationCenter.default.addObserver(forName: .lodyMacReadingDidChange, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.reading = .current() }
    }
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    readingObserver.map(NotificationCenter.default.removeObserver)
  }

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
        composer.view.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, constant: -32),
        composer.view.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
      ]
    } else {
      constraints.append(transcript.bottomAnchor.constraint(equalTo: root.bottomAnchor))
    }
    NSLayoutConstraint.activate(constraints)
    if let composer {
      // A capped column must not imply a maximum width for its split pane or window.
      composerWidths = [
        composer.view.widthAnchor.constraint(lessThanOrEqualToConstant: reading.columnWidth),
        composer.view.widthAnchor.constraint(equalToConstant: reading.columnWidth).withPriority(.init(249)),
      ]
      NSLayoutConstraint.activate(composerWidths)
    }
    transcript.onQuestion = { [weak self] in self?.permission.question($0) }
    transcript.onChanges = { [weak self] entry, files in self?.showChanges(entryId: entry, files: files) }
    transcript.onAnswer = { [weak self] optionId in self?.permission.answer(optionId) }
    transcript.onRetry = { [weak self] in self?.onRetry?() }
    transcript.media = source.media
    transcript.onPreview = { [weak self] in self?.preview($0) }
    if let replies = composer as? MacComposerController {
      if source.diffService != nil { replies.onChanges = { [weak self] in self?.showChanges() } }
      replies.onQueue = { [weak self] in self?.showQueue() }
      replies.onSend = { [weak transcript] in transcript?.noteSend() }
      transcript.onDropFiles = { [weak replies] in replies?.addFiles($0) }
    }
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
    if let queuePage { Task { await queuePage.model.reload() } }
  }

  private func showQueue() {
    guard queuePage == nil, let service = source.queueService else { return }
    let model = MacQueueModel(sessionId: sessionId, userId: source.userId, service: service)
    model.onSteer = { [weak self] in self?.onSteer?($0) }
    model.canSteer = { [weak self] index in
      guard let run = (self?.composer as? MacComposerController)?.model.run else { return false }
      return run.canStop && (!run.steerInterrupts || index == 0)
    }
    let page = MacQueueController(model: model)
    page.reconnect = source.reconnect
    queuePage = page
    presentAsSheet(page)
  }

  private func showChanges(entryId: String? = nil, files: [MacChangedFile] = []) {
    guard diffPage == nil, let service = source.diffService else { return }
    let page = MacDiffController(model: MacDiffModel(sessionId: sessionId, entryId: entryId, files: files, service: service))
    diffPage = page
    presentAsSheet(page)
  }

  private func rebuild() {
    if parsed.json != feed.entriesJSON { parsed = MacTranscriptModel.Parsed(feed.entriesJSON) }
    model = MacTranscriptModel(parsed: parsed, pendingJSON: pendingJSON())
    permission.show(model.permission, ready: feed.status == "live")
    paint()
  }

  private func paint() {
    guard isViewLoaded else { return }
    transcript.render(model)
    if let card = permission.card, let composer {
      if interruption == nil {
        restoreInputFocus = composer.view.descendantsContain(view.window?.firstResponder as? NSView)
        let panel = MacPermissionCard(card: card)
        panel.onQuestion = { [weak self] in self?.permission.question($0) }
        panel.onAnswer = { [weak self] in self?.permission.answer($0) }
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
          panel.leadingAnchor.constraint(equalTo: composer.view.leadingAnchor), panel.trailingAnchor.constraint(equalTo: composer.view.trailingAnchor),
          panel.bottomAnchor.constraint(equalTo: composer.view.bottomAnchor),
        ])
        interruption = panel
      }
      interruption?.update(card)
      composer.view.isHidden = true
    } else {
      let wasPresented = interruption != nil
      interruption?.removeFromSuperview()
      interruption = nil
      composer?.view.isHidden = false
      if wasPresented, restoreInputFocus { (composer as? MacComposerController)?.focusInput() }
      restoreInputFocus = false
    }
  }
}

private extension NSView {
  func descendantsContain(_ other: NSView?) -> Bool {
    guard let other else { return false }
    return other === self || other.isDescendant(of: self)
  }
}
