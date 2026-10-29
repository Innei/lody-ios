import AppKit
import LodyData

@MainActor
protocol MacSessionPane: NSViewController {
  func setStreaming(_ on: Bool)
}

@MainActor
struct MacEnvironment {
  var sessions: MacSessionsSource
  var pane: @MainActor (_ sessionId: String) -> MacSessionPane
  var newSession: @MainActor () -> NSViewController
  var requiresAccount = true
  var windowIdentifier = "main"
  var titlePrefix = ""

  static var live: MacEnvironment {
    MacEnvironment(
      sessions: .live,
      pane: { MacLiveSessionPane.make(sessionId: $0) },
      newSession: { MacNewSessionController(state: SessionPublished.state(), service: .live) }
    )
  }
}

@MainActor
final class MacSessionSummaryPane: NSViewController, MacSessionPane {
  private let sessionId: String
  private let sessions: MacSessionsSource
  private let heading = NSTextField(labelWithString: "")
  private let status = NSTextField(labelWithString: "")
  private(set) var streaming = false

  init(sessionId: String, sessions: MacSessionsSource) {
    self.sessionId = sessionId
    self.sessions = sessions
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  override func loadView() {
    heading.font = .systemFont(ofSize: 17, weight: .semibold)
    status.textColor = .secondaryLabelColor
    status.setAccessibilityIdentifier("session-status")
    let stack = NSStackView(views: [heading, status])
    stack.orientation = .vertical
    stack.translatesAutoresizingMaskIntoConstraints = false
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
    ])
    view = root
    render()
  }

  func setStreaming(_ on: Bool) {
    streaming = on
    render()
  }

  private func render() {
    let session = sessions.read().catalog.session(sessionId)
    heading.stringValue = session?.title ?? ""
    status.stringValue = session?.status ?? ""
  }
}
