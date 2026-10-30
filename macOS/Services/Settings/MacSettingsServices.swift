import AppKit
import LodyData
import Observation

@MainActor
struct MacSettingsServices {
  var source: SettingsSource
  var selectWorkspace: @MainActor (String) -> Void
  var signIn: @MainActor () -> Void
  var general: MacGeneralServices = .live
  var appearance: MacAppearanceServices = .live
  var machines: MacMachineServices = .live
  var workspace: MacWorkspaceServices = .live
  var projects: MacProjectServices = .live
  var about: MacAboutServices = .live

  static var live: MacSettingsServices {
    MacSettingsServices(
      source: .live,
      selectWorkspace: { CatalogSession.shared.selectWorkspace($0) },
      signIn: { (NSApp.delegate as? LodyMacAppDelegate)?.showMain() }
    )
  }
}
