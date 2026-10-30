import AppKit
import LodyData
import Observation
import SwiftUI

@MainActor
@Observable
final class MacAboutModel {
  @ObservationIgnored private let services: MacAboutServices
  @ObservationIgnored private(set) lazy var licenses = services.licenses()
  private(set) var count: Int?
  private(set) var working = false
  var failed = false

  init(services: MacAboutServices) {
    self.services = services
  }

  var version: String {
    let info = services.version()
    return info.build.isEmpty ? info.version : "\(info.version) (\(info.build))"
  }

  func refresh() async {
    count = try? await services.count(services.launched())
  }

  func export() async {
    await run {
      let file = try await self.services.export(self.services.launched())
      await self.services.save(file)
    }
  }

  func clear() async {
    await run { try await self.services.clear() }
    await refresh()
  }

  private func run(_ work: () async throws -> Void) async {
    working = true
    defer { working = false }
    do { try await work() } catch { failed = true }
  }
}
