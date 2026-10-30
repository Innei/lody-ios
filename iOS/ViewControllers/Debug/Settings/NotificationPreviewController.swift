import LodyCore
import UIKit

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
