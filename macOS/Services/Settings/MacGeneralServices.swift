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
