import AppKit
import LodyData
import Observation
import SwiftUI

@MainActor
struct MacAboutServices {
  var version: @MainActor () -> (version: String, build: String)
  var licenses: @MainActor () -> LodyLicenseList
  var launched: @MainActor () -> TimeInterval
  var count: @MainActor (TimeInterval) async throws -> Int
  var export: @MainActor (TimeInterval) async throws -> URL
  var clear: @MainActor () async throws -> Void
  var save: @MainActor (URL) async -> Void

  static var live: MacAboutServices {
    MacAboutServices(
      version: {
        let info = Bundle.main.infoDictionary ?? [:]
        return (info["CFBundleShortVersionString"] as? String ?? "", info["CFBundleVersion"] as? String ?? "")
      },
      licenses: { LodyLicenseList.load(from: Bundle.main.url(forResource: "LodyLicenses", withExtension: "json")) },
      launched: { -(NSRunningApplication.current.launchDate ?? Date()).timeIntervalSinceNow },
      count: { window in try await Task.detached { try DiagnosticsStore.shared.count(since: window) }.value },
      export: { window in try await Task.detached { try DiagnosticsStore.shared.export(since: window) }.value },
      clear: { try await Task.detached { try DiagnosticsStore.shared.clear() }.value },
      save: { file in
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.lastPathComponent
        guard await panel.begin() == .OK, let target = panel.url else { return }
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: file, to: target)
      }
    )
  }
}
