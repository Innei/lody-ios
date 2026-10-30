import LodyCore
import UIKit

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
          LodyShell.shared.push(AppIconController(), title: String(localized: "settings.appearance.appIcon", bundle: .lody), from: self)
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
