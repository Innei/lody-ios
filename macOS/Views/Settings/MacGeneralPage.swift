import LodyData
import Observation
import ServiceManagement
import SwiftUI

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
