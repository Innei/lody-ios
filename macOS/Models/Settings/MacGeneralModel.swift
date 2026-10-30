import LodyData
import Observation
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class MacGeneralModel {
  @ObservationIgnored private let services: MacGeneralServices
  private(set) var notifications: Bool
  private var queued: String
  private var loginStatus: MacLoginItem.Status
  private(set) var loginFailed = false
  @ObservationIgnored private var observers: [NSObjectProtocol] = []

  init(services: MacGeneralServices) {
    self.services = services
    queued = services.queued()
    notifications = services.notifications()
    loginStatus = services.loginItem.status()
    observers = [NSApplication.didBecomeActiveNotification, .lodyPreferencesDidChange].map { name in
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
    }
  }

  isolated deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }

  var steer: Bool {
    get { queued == "guide" }
    set {
      services.saveQueued(newValue ? "guide" : "queue")
      queued = services.queued()
    }
  }

  var login: Bool { loginStatus != .disabled }
  var needsApproval: Bool { loginStatus == .requiresApproval }

  func setNotifications(_ on: Bool) async {
    notifications = on
    notifications = await services.setNotifications(on)
  }

  func setLogin(_ on: Bool) {
    do {
      if on {
        try services.loginItem.register()
      } else {
        try services.loginItem.unregister()
      }
      loginFailed = false
    } catch {
      loginFailed = true
    }
    loginStatus = services.loginItem.status()
  }

  func openLoginItems() {
    services.loginItem.openSystemSettings()
  }

  func refresh() {
    queued = services.queued()
    notifications = services.notifications()
    loginStatus = services.loginItem.status()
  }
}
