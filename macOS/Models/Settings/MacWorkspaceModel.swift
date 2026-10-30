import AppKit
import LodyData
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class MacWorkspaceModel {
  @ObservationIgnored private let services: MacWorkspaceServices
  private var loaded: WorkspaceMembers?
  private var current = ""
  private(set) var loading = false
  private(set) var failed = false
  private(set) var error: String?

  init(services: MacWorkspaceServices) {
    self.services = services
  }

  var members: [WorkspaceMembers.Member] { loaded?.members ?? [] }
  var canEdit: Bool { loaded?.canEdit ?? false }

  func load(workspaceId: String) async {
    if current != workspaceId { loaded = nil }
    current = workspaceId
    loading = true
    let result = await Result { try await services.members(workspaceId) }
    guard current == workspaceId else { return }
    loading = false
    loaded = try? result.get()
    failed = loaded == nil
  }

  func rename(_ workspaceId: String, to name: String) async {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard canEdit, !trimmed.isEmpty else { return }
    await attempt { try await self.services.rename(workspaceId, trimmed) }
  }

  func chooseIcon(_ workspaceId: String) async {
    guard canEdit, let url = await services.pickIcon() else { return }
    await attempt { try await self.services.setIcon(workspaceId, url) }
  }

  private func attempt(_ work: () async throws -> Void) async {
    do {
      try await work()
      error = nil
    } catch {
      self.error = (error as? AuthFailure)?.message ?? String(localized: "mac.settings.failed", bundle: .lodyMac)
    }
  }
}
