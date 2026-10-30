import Foundation
import LodyCore
import LodyData
import Observation

@MainActor
struct MacMachineServices {
  var load: @MainActor (_ workspaceId: String) async throws -> [MacMachine]
  var rename: @MainActor (_ workspaceId: String, MacMachine, String) async throws -> [MacMachine]
  var presence: @MainActor () -> SettingsMachinePresence

  private struct Edit: Encodable {
    var item: MacMachine
    var name: String
  }

  private struct Request: Encodable {
    var workspaceId: String
    var kind = "machine"
    var edit: Edit?
  }

  static var live: MacMachineServices {
    MacMachineServices(
      load: { try await call(Request(workspaceId: $0)) },
      rename: { workspace, machine, name in try await call(Request(workspaceId: workspace, edit: Edit(item: machine, name: name))) },
      presence: {
        let workspace = SettingsWorkspace.decode(state: CatalogSession.published.json, raw: CatalogSession.published.raw)
        return workspace.connected ? workspace.presence : .unknown
      }
    )
  }

  private static func call(_ request: Request) async throws -> [MacMachine] {
    let items = try await DataRuntime.settingsCall(RuntimeContract.Calls.RemoteSettings.self, request, as: [MacMachine].self) { $0.settings }
    return items.filter { $0.kind == "machine" }
  }
}
