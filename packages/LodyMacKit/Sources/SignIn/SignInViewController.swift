import AppKit
import LodyData

@MainActor
struct SignInService {
  var snapshot: () -> AuthSnapshot
  var login: () async throws -> Void
  var cancel: () -> Void
  var reopen: () -> Void
  var changes: Notification.Name = .lodyAuthDidChange

  static let live = SignInService(
    snapshot: { AuthSession.shared.snapshot },
    login: { try await AuthSession.shared.login() },
    cancel: { AuthSession.shared.cancel() },
    reopen: { AuthSession.shared.reopen() }
  )
}

@MainActor
final class SignInViewController: NSViewController {
  private let service: SignInService
  private let title1 = NSTextField(labelWithString: String(localized: "mac.signIn.title", bundle: .lodyMac))
  private let detail = NSTextField(wrappingLabelWithString: String(localized: "mac.signIn.detail", bundle: .lodyMac))
  private let code = NSTextField(labelWithString: "")
  private let status = NSTextField(wrappingLabelWithString: "")
  private let primary = NSButton(title: String(localized: "mac.signIn.start", bundle: .lodyMac), target: nil, action: nil)
  private let secondary = NSButton(title: String(localized: "mac.signIn.cancel", bundle: .lodyMac), target: nil, action: nil)
  private var observer: NSObjectProtocol?

  init(service: SignInService = .live) {
    self.service = service
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 420))
    title1.font = .systemFont(ofSize: 22, weight: .semibold)
    detail.alignment = .center
    detail.textColor = .secondaryLabelColor
    detail.preferredMaxLayoutWidth = 360
    code.font = .monospacedSystemFont(ofSize: 28, weight: .semibold)
    code.isSelectable = true
    code.setAccessibilityIdentifier("sign-in-code")
    status.alignment = .center
    status.textColor = .secondaryLabelColor
    status.preferredMaxLayoutWidth = 360
    primary.bezelStyle = .push
    primary.keyEquivalent = "\r"
    primary.controlSize = .large
    primary.target = self
    primary.action = #selector(primaryPressed)
    secondary.bezelStyle = .push
    secondary.controlSize = .large
    secondary.target = self
    secondary.action = #selector(secondaryPressed)
    let buttons = NSStackView(views: [secondary, primary])
    buttons.spacing = 12
    let stack = NSStackView(views: [title1, detail, code, status, buttons])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 14
    stack.setCustomSpacing(24, after: status)
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 32),
    ])
    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    observer = NotificationCenter.default.addObserver(forName: service.changes, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.render() }
    }
    render()
  }

  private func render() {
    let state = service.snapshot()
    code.stringValue = state.code?.user_code ?? ""
    code.isHidden = state.code == nil
    secondary.isHidden = state.code == nil
    if let error = state.error {
      status.stringValue = error
      status.textColor = .systemRed
    } else if state.code != nil {
      status.stringValue = String(localized: "mac.signIn.waiting", bundle: .lodyMac)
      status.textColor = .secondaryLabelColor
    } else {
      status.stringValue = ""
    }
    primary.title = String(localized: state.code == nil ? "mac.signIn.start" : "mac.signIn.reopen", bundle: .lodyMac)
    primary.isEnabled = state.code != nil || !state.busy
  }

  @objc private func primaryPressed() {
    if service.snapshot().code != nil { service.reopen(); return }
    Task { try? await service.login() }
  }

  @objc private func secondaryPressed() { service.cancel() }
}
