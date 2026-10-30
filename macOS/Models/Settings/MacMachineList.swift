import Foundation
import LodyCore
import LodyData
import Observation

@MainActor
@Observable
final class MacMachineList {
  @ObservationIgnored private let services: MacMachineServices
  private var machines: [MacMachine] = []
  private var cache: [String: [MacMachine]] = [:]
  private var workspaceId = ""
  private var presence: SettingsMachinePresence
  private(set) var loading = false
  private(set) var failed = false
  private(set) var waiting = false
  var renameFailed = false

  init(services: MacMachineServices) {
    self.services = services
    presence = services.presence()
  }

  var rows: [MacMachineRow] {
    machines.map { MacMachineRow(machine: $0, status: presence.status(of: $0.id)) }
  }

  var owned: [MacMachineRow] { rows.filter(\.owned) }

  func show(workspaceId: String) {
    self.workspaceId = workspaceId
    machines = cache[workspaceId] ?? []
  }

  func load(workspaceId: String) async {
    show(workspaceId: workspaceId)
    loading = true
    defer { loading = false }
    do {
      store(try await services.load(workspaceId), for: workspaceId)
      failed = false
      waiting = false
    } catch {
      waiting = Self.notReady(error)
      failed = !waiting && cache[workspaceId] == nil
    }
    presence = services.presence()
  }

  func retryIfWaiting() async {
    guard waiting, !loading, !workspaceId.isEmpty else { return }
    await load(workspaceId: workspaceId)
  }

  private static func notReady(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == "LodyKit.DataRuntime" && error.localizedDescription.hasPrefix("not_ready:")
  }

  func rename(_ row: MacMachineRow, to name: String, workspaceId: String) async {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard row.canRename, !trimmed.isEmpty, trimmed != row.machine.name else { return }
    do {
      store(try await services.rename(workspaceId, row.machine, trimmed), for: workspaceId)
      failed = false
    } catch {
      renameFailed = true
    }
  }

  private func store(_ next: [MacMachine], for workspace: String) {
    cache[workspace] = next
    if workspace == workspaceId { machines = next }
  }

  func refreshPresence() {
    presence = services.presence()
  }
}
