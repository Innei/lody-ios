import AppKit
import LodyData

@MainActor
struct SignInService {
  var snapshot: () -> AuthSnapshot
  var login: () async throws -> Void
  var cancel: () -> Void
  var reopen: () -> Void
  var changes: Notification.Name = .lodyAuthDidChange
  var copy: (String) -> Void = { text in
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

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
  private let motion: MacJellyfishMotion
  private lazy var visual = MacJellyfishView(motion: motion)
  private let heading = NSTextField(labelWithString: "")
  private let detail = NSTextField(wrappingLabelWithString: "")
  private let code = NSTextField(labelWithString: "")
  private let copyButton = NSButton()
  private let card = NSView()
  private let spinner = NSProgressIndicator()
  private let status = NSTextField(wrappingLabelWithString: "")
  private lazy var statusRow = NSStackView(views: [spinner, status])
  private let primary = NSButton(title: "", target: nil, action: nil)
  private let cancel = NSButton(title: String(localized: "mac.signIn.cancel", bundle: .lodyMac), target: nil, action: nil)
  private lazy var actions = NSStackView(views: [primary, cancel])
  private let providers = NSTextField(wrappingLabelWithString: String(localized: "mac.signIn.providers", bundle: .lodyMac))
  private let rule = NSBox()
  private let legal = NSTextField(labelWithAttributedString: MacSignInCopy.legalText())
  private let column = NSStackView()
  private var observer: NSObjectProtocol?
  private var ticker: Timer?
  private var issued: (code: String, at: Date)?
  private var signedInName: String?
  private var entered = false

  init(service: SignInService = .live, motion: MacJellyfishMotion = .system) {
    self.service = service
    self.motion = motion
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    ticker?.invalidate()
  }

  override func loadView() {
    let root = NSView(frame: NSRect(origin: .zero, size: MacOnboardingChrome.size))
    root.wantsLayer = true
    let panel = NSView()
    panel.wantsLayer = true
    panel.layer?.cornerRadius = 8
    panel.layer?.masksToBounds = true
    visual.translatesAutoresizingMaskIntoConstraints = false
    panel.addSubview(visual)
    configureControls()
    let full: [NSView] = [detail, card, statusRow, actions, providers, rule, legal]
    for view in [heading] + full { column.addArrangedSubview(view) }
    column.orientation = .vertical
    column.alignment = .leading
    column.spacing = 8
    column.setCustomSpacing(22, after: detail)
    column.setCustomSpacing(14, after: card)
    column.setCustomSpacing(22, after: statusRow)
    column.setCustomSpacing(10, after: actions)
    column.setCustomSpacing(18, after: providers)
    column.setCustomSpacing(12, after: rule)
    for view in [panel, column] {
      view.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(view)
    }
    NSLayoutConstraint.activate([
      panel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
      panel.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
      panel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
      panel.widthAnchor.constraint(equalToConstant: 464),
      visual.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
      visual.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
      visual.topAnchor.constraint(equalTo: panel.topAnchor),
      visual.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
      column.leadingAnchor.constraint(equalTo: panel.trailingAnchor, constant: 40),
      column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -44),
      column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -28),
      column.topAnchor.constraint(greaterThanOrEqualTo: root.topAnchor, constant: 40),
    ] + full.map { $0.widthAnchor.constraint(equalTo: column.widthAnchor) })
    view = root
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    observer = NotificationCenter.default.addObserver(forName: service.changes, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.render() }
    }
    render()
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    visual.start()
    guard !entered else { return }
    entered = true
    if !motion.reduceMotion { riseIn() }
  }

  override func viewWillDisappear() {
    super.viewWillDisappear()
    ticker?.invalidate()
    ticker = nil
  }

  func finish(name: String, completion: @escaping @MainActor () -> Void) {
    signedInName = name
    render()
    visual.leave(completion: completion)
  }

  private func configureControls() {
    heading.font = .systemFont(ofSize: 26, weight: .semibold)
    heading.setAccessibilityIdentifier("sign-in-heading")
    detail.textColor = .secondaryLabelColor
    code.font = .monospacedSystemFont(ofSize: 26, weight: .semibold)
    code.isSelectable = true
    code.setAccessibilityIdentifier("sign-in-code")
    let copyLabel = String(localized: "mac.signIn.copy", bundle: .lodyMac)
    copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: copyLabel)
    copyButton.isBordered = false
    copyButton.contentTintColor = .secondaryLabelColor
    copyButton.toolTip = copyLabel
    copyButton.setAccessibilityLabel(copyLabel)
    copyButton.setAccessibilityIdentifier("sign-in-copy")
    copyButton.target = self
    copyButton.action = #selector(copyPressed)
    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    let inside = NSStackView(views: [code, spacer, copyButton])
    inside.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 14)
    inside.translatesAutoresizingMaskIntoConstraints = false
    card.wantsLayer = true
    card.layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
    card.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
    card.layer?.borderWidth = 0.5
    card.layer?.cornerRadius = 12
    card.addSubview(inside)
    NSLayoutConstraint.activate([
      inside.leadingAnchor.constraint(equalTo: card.leadingAnchor),
      inside.trailingAnchor.constraint(equalTo: card.trailingAnchor),
      inside.topAnchor.constraint(equalTo: card.topAnchor),
      inside.bottomAnchor.constraint(equalTo: card.bottomAnchor),
    ])
    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false
    status.font = .systemFont(ofSize: 12)
    statusRow.spacing = 8
    primary.bezelStyle = .push
    primary.controlSize = .large
    primary.keyEquivalent = "\r"
    primary.setAccessibilityIdentifier("sign-in-primary")
    primary.setContentHuggingPriority(.defaultLow, for: .horizontal)
    primary.target = self
    primary.action = #selector(primaryPressed)
    cancel.bezelStyle = .push
    cancel.controlSize = .large
    cancel.setAccessibilityIdentifier("sign-in-cancel")
    cancel.target = self
    cancel.action = #selector(cancelPressed)
    actions.spacing = 8
    actions.distribution = .fill
    providers.font = .systemFont(ofSize: 12)
    providers.textColor = .secondaryLabelColor
    rule.boxType = .separator
    legal.isSelectable = true
    legal.allowsEditingTextAttributes = true
    legal.setAccessibilityIdentifier("sign-in-legal")
  }

  private var expired: Bool {
    guard let issued, let expires = service.snapshot().code?.expires_in else { return false }
    return MacSignInCopy.minutesLeft(expires - Date().timeIntervalSince(issued.at)) == nil
  }

  private func render() {
    if let signedInName {
      heading.stringValue = String(format: String(localized: "mac.signIn.done", bundle: .lodyMac), signedInName)
      detail.stringValue = String(localized: "mac.signIn.done.detail", bundle: .lodyMac)
      for view in [card, code, statusRow, actions, providers, rule, legal] { view.isHidden = true }
      ticker?.invalidate()
      return
    }
    let state = service.snapshot()
    if let current = state.code {
      if issued?.code != current.user_code { issued = (current.user_code, Date()) }
    } else {
      issued = nil
    }
    let waiting = state.code != nil
    heading.stringValue = String(localized: waiting ? "mac.signIn.confirm" : "mac.signIn.welcome", bundle: .lodyMac)
    detail.stringValue = String(localized: waiting ? "mac.signIn.confirm.detail" : "mac.signIn.welcome.detail", bundle: .lodyMac)
    code.stringValue = state.code?.user_code ?? ""
    for view in [card, code, cancel] { view.isHidden = !waiting }
    for view in [providers, rule, legal] { view.isHidden = waiting }
    actions.isHidden = false
    renderStatus(state, waiting: waiting)
    primary.isEnabled = waiting || !state.busy
    if waiting, ticker == nil {
      ticker = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.render() }
      }
    } else if !waiting {
      ticker?.invalidate()
      ticker = nil
    }
  }

  private func renderStatus(_ state: AuthSnapshot, waiting: Bool) {
    primary.title = String(localized: waiting ? "mac.signIn.reopen" : "mac.signIn.continue", bundle: .lodyMac)
    statusRow.isHidden = !waiting && state.error == nil
    if let error = state.error {
      status.stringValue = error
      status.textColor = .systemRed
      spinner.stopAnimation(nil)
    } else if waiting, expired {
      status.stringValue = String(localized: "mac.signIn.expired", bundle: .lodyMac)
      status.textColor = .secondaryLabelColor
      spinner.stopAnimation(nil)
      primary.title = String(localized: "mac.signIn.restart", bundle: .lodyMac)
    } else if waiting, let issued, let expires = state.code?.expires_in,
              let minutes = MacSignInCopy.minutesLeft(expires - Date().timeIntervalSince(issued.at)) {
      status.stringValue = String(format: String(localized: "mac.signIn.waiting", bundle: .lodyMac), minutes)
      status.textColor = .secondaryLabelColor
      spinner.startAnimation(nil)
    }
  }

  private func riseIn() {
    let start = CACurrentMediaTime() + 0.3
    for (index, view) in column.arrangedSubviews.filter({ !$0.isHidden }).enumerated() {
      view.wantsLayer = true
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0
      fade.toValue = 1
      let rise = CABasicAnimation(keyPath: "transform.translation.y")
      rise.fromValue = -10
      rise.toValue = 0
      let group = CAAnimationGroup()
      group.animations = [fade, rise]
      group.duration = 0.5
      group.beginTime = start + Double(index) * 0.06
      group.fillMode = .backwards
      group.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
      view.layer?.add(group, forKey: "lody.rise")
    }
  }

  @objc private func primaryPressed() {
    let waiting = service.snapshot().code != nil
    if waiting, !expired {
      service.reopen()
      return
    }
    if waiting { service.cancel() }
    Task { try? await service.login() }
  }

  @objc private func cancelPressed() { service.cancel() }

  @objc private func copyPressed() {
    service.copy(code.stringValue)
    copyButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: copyButton.accessibilityLabel())
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
      MainActor.assumeIsolated {
        self?.copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: self?.copyButton.accessibilityLabel())
      }
    }
  }

}
