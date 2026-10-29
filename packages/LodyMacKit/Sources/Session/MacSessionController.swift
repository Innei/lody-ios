import AppKit
import LodyCore
import LodyData

@MainActor
struct MacTranscriptSource {
  var start: @MainActor (_ changed: @escaping @MainActor (String) -> Void) -> Void
  var stop: @MainActor () -> Void
  var answer: @MainActor (SessionPermission, String) async throws -> Void

  static func live(sessionId: String, state: SessionListState, permission: PermissionService = .live) -> MacTranscriptSource {
    let feed = SessionFeed(sessionId: sessionId, userId: state.userId, workspaceId: state.workspaceId)
    return MacTranscriptSource(
      start: { changed in
        feed.changed = { [weak feed] in if let feed { changed(feed.state.entriesJSON) } }
        feed.start()
      },
      stop: { feed.finish() },
      answer: { target, optionId in
        _ = try await permission.respond(.init(
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
  private var model = MacTranscriptModel(entriesJSON: "[]")
  private var streaming = false

  init(sessionId: String, source: MacTranscriptSource, composer: NSViewController? = nil) {
    self.sessionId = sessionId
    self.source = source
    self.composer = composer
    super.init(nibName: nil, bundle: nil)
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
    transcript.onAnswer = { [weak self] optionId in self?.answer(optionId) }
    view = root
  }

  func setStreaming(_ on: Bool) {
    guard on != streaming else { return }
    streaming = on
    if on {
      source.start { [weak self] json in self?.render(json) }
    } else {
      source.stop()
    }
  }

  private func render(_ json: String) {
    model = MacTranscriptModel(entriesJSON: json)
    transcript.render(model)
  }

  private func answer(_ optionId: String) {
    guard let target = model.permission else { return }
    Task { [source] in
      do { try await source.answer(target, optionId) } catch {
        LodyHosting.current?.toast(String(localized: "mac.permission.failed", bundle: .lodyMac), kind: "error")
      }
    }
  }
}
