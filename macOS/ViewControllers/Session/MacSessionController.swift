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
  private var interruptionWidth: NSLayoutConstraint?
  private var restoreInputFocus = false
  private var model = MacTranscriptModel(entriesJSON: "[]")
  private var parsed = MacTranscriptModel.Parsed("[]")
  private var feed = SessionFeedState()
  private var streaming = false
  private var composerWidths: [NSLayoutConstraint] = []
  private var readingObserver: NSObjectProtocol?
  private var queuePage: MacQueueController?
  private var queueHeight: NSLayoutConstraint?
  private var queueGap: NSLayoutConstraint?
  var onSteer: ((String) -> Void)?
  var inspectionModel: MacInspectionModel?
  var onInspect: (() -> Void)?
  var previewURL: URL?
  var transcriptMedia: CKMediaProvider? { source.media }
  var transcriptPreview: (@MainActor (CKMediaRef) async throws -> MacInspectionContent)? { source.previewFile }
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
      if let service = source.queueService {
        let queued = MacQueueModel(sessionId: sessionId, userId: source.userId, service: service)
        queued.onSteer = { [weak self] in self?.onSteer?($0) }
        queued.canSteer = { [weak self] index in
          guard let run = (self?.composer as? MacComposerController)?.model.run else { return false }
          return run.canStop && (!run.steerInterrupts || index == 0)
        }
        let page = MacQueueController(model: queued)
        page.reconnect = source.reconnect
        page.onHeightChange = { [weak self] in self?.placeQueue() }
        queuePage = page
        addChild(page)
        page.view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(page.view, positioned: .below, relativeTo: composer.view)
        let height = page.view.heightAnchor.constraint(equalToConstant: 0)
        let gap = page.view.bottomAnchor.constraint(equalTo: composer.view.topAnchor)
        queueHeight = height
        queueGap = gap
        constraints += [height, gap, page.view.widthAnchor.constraint(equalTo: composer.view.widthAnchor, constant: -2 * MacComposerTrayView.sideInset), page.view.centerXAnchor.constraint(equalTo: composer.view.centerXAnchor), transcript.bottomAnchor.constraint(equalTo: page.view.topAnchor)]
      } else { constraints.append(transcript.bottomAnchor.constraint(equalTo: composer.view.topAnchor)) }
      constraints += [
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
    transcript.onRetry = { [weak self] in self?.onRetry?() }
    transcript.media = source.media
    transcript.onPreview = { [weak self] in self?.preview($0) }
    transcript.onChanges = { [weak self] id in self?.inspectChanges(row: id) }
    if let replies = composer as? MacComposerController {
      replies.onRunChange = { [weak self] in self?.queuePage?.refreshControls() }
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
      inspectionModel?.resumeIfReady()
    } else {
      inspectionModel?.suspend()
      source.stop()
    }
  }

  override func viewDidLayout() {
    super.viewDidLayout()
    interruptionWidth?.constant = composer?.view.frame.width ?? 0
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
    if streaming, state.status == "live" { inspectionModel?.resumeIfReady() }
    if let queuePage { Task { await queuePage.model.reload() } }
  }

  private func placeQueue() {
    guard isViewLoaded, let page = queuePage else { return }
    let visible = permission.card == nil && page.preferredContentSize.height > 0
    page.view.isHidden = !visible
    queueHeight?.constant = visible ? page.preferredContentSize.height : 0
    queueGap?.constant = visible ? MacComposerTrayView.overlap : 0
  }

  private func rebuild() {
    if parsed.json != feed.entriesJSON { parsed = MacTranscriptModel.Parsed(feed.entriesJSON) }
    model = MacTranscriptModel(parsed: parsed, pendingJSON: pendingJSON())
    updateInspectionEntries()
    permission.show(model.permission, ready: feed.status == "live")
    paint()
  }

  private func updateInspectionEntries() {
    guard let inspectionModel, let entries = parsed.entries else { return }
    inspectionModel.latestTurn = entries.reversed().compactMap { entry -> MacInspectionTurn? in
      let files = (entry.fileDiffs ?? []).filter { !$0.path.isEmpty }.map { MacInspectionFile(path: $0.path, add: $0.add, del: $0.del, kind: $0.status) }
      guard !files.isEmpty else { return nil }
      return MacInspectionTurn(id: entry.id, title: entry.timestamp ?? MacInspectionUI.text("mac.inspection.thisTurn"), files: files)
    }.first
  }

  private func inspectChanges(row: String) {
    guard let inspectionModel, let entryID = model.groups[row], let entry = parsed.entries?.first(where: { $0.id == entryID }) else { return }
    let files = (entry.fileDiffs ?? []).filter { !$0.path.isEmpty }.map { MacInspectionFile(path: $0.path, add: $0.add, del: $0.del, kind: $0.status) }
    inspectionModel.showChanges(entry: .init(id: entry.id, title: entry.timestamp ?? MacInspectionUI.text("mac.inspection.thisTurn"), files: files), path: model.changedPaths[row])
    onInspect?()
  }

  private func paint() {
    guard isViewLoaded else { return }
    transcript.render(model)
    placeQueue()
    if let card = permission.card, let composer {
      if interruption == nil {
        restoreInputFocus = composer.view.descendantsContain(view.window?.firstResponder as? NSView)
        let panel = MacPermissionCard(card: card)
        panel.onQuestion = { [weak self] in self?.permission.question($0) }
        panel.onAnswer = { [weak self] in self?.permission.answer($0) }
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        // The input owns its column. The overlay's label hugging must never
        // feed back into the composer's deliberately soft width preference.
        let width = panel.widthAnchor.constraint(equalToConstant: composer.view.frame.width)
        interruptionWidth = width
        NSLayoutConstraint.activate([
          width, panel.centerXAnchor.constraint(equalTo: composer.view.centerXAnchor),
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
      interruptionWidth = nil
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
