import LodyData
import Observation
import ServiceManagement
import SwiftUI

@MainActor
struct MacLoginItem {
  enum Status { case enabled, disabled, requiresApproval }

  var status: @MainActor () -> Status
  var register: @MainActor () throws -> Void
  var unregister: @MainActor () throws -> Void
  var openSystemSettings: @MainActor () -> Void

  static var live: MacLoginItem {
    MacLoginItem(
      status: {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .disabled
        }
      },
      register: { try SMAppService.mainApp.register() },
      unregister: { try SMAppService.mainApp.unregister() },
      openSystemSettings: { SMAppService.openSystemSettingsLoginItems() }
    )
  }
}

@MainActor
struct MacGeneralServices {
  var queued: @MainActor () -> String
  var saveQueued: @MainActor (String) -> Void
  var notifications: @MainActor () -> Bool
  var setNotifications: @MainActor (Bool) async -> Bool
  var loginItem: MacLoginItem

  static var live: MacGeneralServices {
    MacGeneralServices(
      queued: { LodyPreferences.queuedMessageBehavior },
      saveQueued: { LodyPreferences.saveQueuedMessageBehavior($0) },
      notifications: { MacNotifier.shared.enabled },
      setNotifications: { await MacNotifier.shared.setEnabled($0) },
      loginItem: .live
    )
  }
}

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

struct MacGeneralPage: View {
  @Bindable var model: MacGeneralModel

  var body: some View {
    Form {
      Section(String(localized: "mac.settings.section.conversations", bundle: .lodyMac)) {
        Picker(selection: $model.steer) {
          Text(String(localized: "mac.settings.queue.queue", bundle: .lodyMac)).tag(false)
          Text(String(localized: "mac.settings.queue.steer", bundle: .lodyMac)).tag(true)
        } label: {
          Text(String(localized: "mac.settings.queue.title", bundle: .lodyMac))
          Text(String(localized: "mac.settings.queue.detail", bundle: .lodyMac))
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityIdentifier("settings-general-queue")
      }
      Section(String(localized: "mac.settings.notifications", bundle: .lodyMac)) {
        Toggle(isOn: Binding(get: { model.notifications }, set: { on in Task { await model.setNotifications(on) } })) {
          Text(String(localized: "mac.settings.desktopNotifications", bundle: .lodyMac))
          Text(String(localized: "mac.settings.notifications.detail", bundle: .lodyMac))
        }
        .accessibilityIdentifier("settings-general-notifications")
      }
      Section(String(localized: "mac.settings.section.startup", bundle: .lodyMac)) {
        Toggle(isOn: Binding(get: { model.login }, set: { model.setLogin($0) })) {
          Text(String(localized: "mac.settings.login", bundle: .lodyMac))
          Text(String(localized: "mac.settings.login.detail", bundle: .lodyMac))
        }
        .accessibilityIdentifier("settings-general-login")
        if model.loginFailed {
          Text(String(localized: "mac.settings.login.failed", bundle: .lodyMac)).foregroundStyle(.secondary)
        }
        if model.needsApproval {
          LabeledContent(String(localized: "mac.settings.login.approval", bundle: .lodyMac)) {
            Button(String(localized: "mac.settings.login.openSettings", bundle: .lodyMac)) { model.openLoginItems() }
          }
        }
      }
    }
    .formStyle(.grouped)
  }
}
