import LodyCore
import LodyData
import Observation

struct MacMachine: Codable, Equatable, Identifiable, Sendable {
  var kind = "machine"
  var id: String
  var name: String
  var detail: String?
  var readOnly: Bool?

  init(id: String, name: String, detail: String?, readOnly: Bool?) {
    self.id = id
    self.name = name
    self.detail = detail
    self.readOnly = readOnly
  }
}

struct MacMachineRow: Equatable, Identifiable {
  let machine: MacMachine
  let status: String
  var id: String { machine.id }
  var name: String { machine.name.isEmpty ? machine.id : machine.name }
  var owned: Bool { machine.readOnly == false }
}

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

@MainActor
@Observable
final class MacMachineList {
  @ObservationIgnored private let services: MacMachineServices
  private var machines: [MacMachine] = []
  private var presence: SettingsMachinePresence
  private(set) var loading = false
  private(set) var failed = false

  init(services: MacMachineServices) {
    self.services = services
    presence = services.presence()
  }

  var rows: [MacMachineRow] {
    machines.map { MacMachineRow(machine: $0, status: presence.status(of: $0.id)) }
  }

  var owned: [MacMachineRow] { rows.filter(\.owned) }

  func load(workspaceId: String) async {
    loading = true
    defer { loading = false }
    do {
      machines = try await services.load(workspaceId)
      failed = false
    } catch {
      machines = []
      failed = true
    }
    presence = services.presence()
  }

  func refreshPresence() {
    presence = services.presence()
  }
}
