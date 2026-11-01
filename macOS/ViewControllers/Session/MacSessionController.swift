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
  private var model = MacTranscriptModel(entriesJSON: "[]")
  private var parsed = MacTranscriptModel.Parsed("[]")
  private var feed = SessionFeedState()
  private var streaming = false
  private var composerWidths: [NSLayoutConstraint] = []
  private var readingObserver: NSObjectProtocol?
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
    transcript.onAnswer = { [weak self] optionId in self?.permission.answer(optionId) }
    transcript.onRetry = { [weak self] in self?.onRetry?() }
    transcript.media = source.media
    transcript.onPreview = { [weak self] in self?.preview($0) }
    if let replies = composer as? MacComposerController {
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
  }

  private func rebuild() {
    if parsed.json != feed.entriesJSON { parsed = MacTranscriptModel.Parsed(feed.entriesJSON) }
    model = MacTranscriptModel(parsed: parsed, pendingJSON: pendingJSON())
    permission.show(model.permission, ready: feed.status == "live")
    paint()
  }

  private func paint() {
    guard isViewLoaded else { return }
    transcript.render(model, card: permission.card)
  }
}
