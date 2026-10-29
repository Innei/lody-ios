import UIKit

@MainActor
class NotificationPreviewHost: UIViewController {
  let header = UIStackView()
  private(set) var content: NotificationSettingsController?

  var service: NotificationService { .live }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    header.axis = .vertical
    header.alignment = .leading
    header.spacing = 8
    header.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(header)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
    ])
    mount()
  }

  func mount() {
    content.map { old in
      old.willMove(toParent: nil)
      old.view.removeFromSuperview()
      old.removeFromParent()
    }
    let next = NotificationSettingsController(service: service, signedIn: { true })
    addChild(next)
    next.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(next.view)
    NSLayoutConstraint.activate([
      next.view.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
      next.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      next.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      next.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    next.didMove(toParent: self)
    content = next
  }

  static func label(_ id: String?, _ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.textColor = .label
    label.font = .preferredFont(forTextStyle: .body)
    label.accessibilityIdentifier = id
    return label
  }

  static func button(_ id: String, _ title: String, _ action: @escaping @MainActor () -> Void) -> UIButton {
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
    button.accessibilityIdentifier = id
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    return button
  }
}

@MainActor
final class NotificationPreviewController: NotificationPreviewHost {
  private final class Fixture {
    var permission = "notDetermined"
    var enabled = false
    var requests = 0
    var settingsAttempts = 0
    var liveWrites = 0
  }

  private struct FixtureFailure: Error {}

  private let fixture = Fixture()
  private let opened = NotificationPreviewHost.label(nil, "Settings not opened")
  private let writes = NotificationPreviewHost.label("notification-live-writes", "Live changes: 0")

  override var service: NotificationService {
    let fixture = fixture
    return NotificationService(
      status: { NotificationService.Push(configured: true, permission: fixture.permission) },
      request: {
        fixture.requests += 1
        if fixture.requests == 1 { throw FixtureFailure() }
        fixture.permission = "denied"
        return false
      },
      settings: { [weak self] in
        if fixture.permission == "denied" {
          fixture.settingsAttempts += 1
          if fixture.settingsAttempts == 1 { throw FixtureFailure() }
        }
        fixture.permission = "authorized"
        self?.setOpened(true)
      },
      liveStatus: { NotificationService.Live(enabled: fixture.enabled, supported: fixture.permission == "authorized") },
      setLiveEnabled: { [weak self] next in
        fixture.liveWrites += 1
        self?.writes.text = "Live changes: \(fixture.liveWrites)"
        if !next { throw FixtureFailure() }
        fixture.enabled = next
      }
    )
  }

  override func viewDidLoad() {
    title = "Notification fixture"
    for view in [
      Self.label("notification-preview-ready", "Notification permission fixture"),
      opened,
      Self.button("notification-reset", "Reset") { [weak self] in self?.reset() },
      writes,
    ] as [UIView] {
      header.addArrangedSubview(view)
    }
    super.viewDidLoad()
  }

  private func setOpened(_ value: Bool) {
    opened.text = value ? "Returned from Settings" : "Settings not opened"
    opened.accessibilityIdentifier = value ? "notification-settings-opened" : nil
  }

  private func reset() {
    fixture.liveWrites = 0
    writes.text = "Live changes: 0"
    setOpened(false)
    mount()
  }
}

@MainActor
final class LiveActivityPreviewController: NotificationPreviewHost {
  private final class Fixture {
    var enabled = true
  }

  private let fixture = Fixture()
  private let status = NotificationPreviewHost.label("live-activity-status", "0 active")
  private var timer: Timer?

  override var service: NotificationService {
    let fixture = fixture
    return NotificationService(
      status: { NotificationService.Push(configured: true, permission: "authorized") },
      request: { true },
      settings: {},
      liveStatus: { NotificationService.Live(enabled: fixture.enabled, supported: true) },
      setLiveEnabled: { fixture.enabled = $0 }
    )
  }

  isolated deinit { timer?.invalidate() }

  override func viewDidLoad() {
    title = "Live Activity fixture"
    let debug: [(String, String, String)] = [
      ("live-activity-start", "Start (running)", "start-running"),
      ("live-activity-permission", "Switch to needs approval", "update-permission"),
      ("live-activity-end", "End", "end"),
      ("live-activity-complete-one", "Complete one task", "complete-one"),
      ("live-activity-complete-all", "Complete all", "complete-all"),
      ("live-activity-fail-all", "Fail all", "fail-all"),
    ]
    var views: [UIView] = [Self.label("live-activity-preview-ready", "Live Activity fixture"), status]
    for (id, title, action) in debug {
      views.append(Self.button(id, title) { LiveActivities.shared.debug(action) })
      if id == "live-activity-start" {
        views.append(Self.button("live-activity-icon", "App Icon") { [weak self] in
          guard let self else { return }
          LodyShell.shared.pushNative(AppIconController(), title: String(localized: "settings.appearance.appIcon", bundle: .lody), from: self)
        })
      }
    }
    views.forEach(header.addArrangedSubview)
    super.viewDidLoad()
    refreshStatus()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshStatus() }
    }
  }

  private func refreshStatus() {
    status.text = "\(LiveActivities.shared.status()["active"] as? Int ?? 0) active"
  }
}
