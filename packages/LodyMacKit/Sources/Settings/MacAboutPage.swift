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

struct MacAboutPage: View {
  @Bindable var model: MacAboutModel
  @State private var showsLicenses = false

  var body: some View {
    Form {
      Section {
        VStack(spacing: 6) {
          Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 72, height: 72)
            .accessibilityHidden(true)
          Text(verbatim: "Lody").font(.title2.weight(.semibold))
          Text(String(format: String(localized: "mac.settings.version.value", bundle: .lodyMac), model.version))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .accessibilityIdentifier("settings-about-version")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      }
      Section {
        LabeledContent(String(localized: "mac.settings.licenses", bundle: .lodyMac)) {
          Button(String(localized: "mac.settings.licenses.show", bundle: .lodyMac)) { showsLicenses = true }
            .accessibilityIdentifier("settings-about-licenses")
        }
      }
      Section {
        LabeledContent {
          HStack {
            Button(String(localized: "mac.settings.diagnostics.export", bundle: .lodyMac)) { Task { await model.export() } }
              .accessibilityIdentifier("settings-about-export")
            Button(String(localized: "mac.settings.diagnostics.clear", bundle: .lodyMac)) { Task { await model.clear() } }
              .accessibilityIdentifier("settings-about-clear")
          }
          .disabled(model.working)
        } label: {
          Text(String(localized: "mac.settings.diagnostics", bundle: .lodyMac))
          if let count = model.count {
            Text(String(format: String(localized: "mac.settings.diagnostics.count", bundle: .lodyMac), count))
          }
        }
      }
    }
    .formStyle(.grouped)
    .task { await model.refresh() }
    .sheet(isPresented: $showsLicenses) { MacLicensesSheet(list: model.licenses) }
    .alert(String(localized: "mac.settings.failed", bundle: .lodyMac), isPresented: $model.failed) {
      Button(String(localized: "mac.settings.ok", bundle: .lodyMac), role: .cancel) {}
    }
  }
}

struct MacLicensesSheet: View {
  let list: LodyLicenseList
  @Environment(\.dismiss) private var dismiss
  @State private var selection: String?

  var body: some View {
    VStack(spacing: 0) {
      HSplitView {
        List(list.packages, id: \.name, selection: $selection) { entry in
          VStack(alignment: .leading, spacing: 1) {
            Text(entry.name)
            Text([entry.version, entry.license].compactMap { $0 }.joined(separator: " · "))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        .frame(minWidth: 200, idealWidth: 220)
        ScrollView {
          Text(selection.flatMap(list.entry).map(list.text) ?? "")
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(minWidth: 320)
      }
      Divider()
      HStack {
        Spacer()
        Button(String(localized: "mac.settings.done", bundle: .lodyMac)) { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(12)
    }
    .frame(width: 680, height: 460)
    .onAppear { selection = list.packages.first(where: { $0.firstParty == true })?.name ?? list.packages.first?.name }
    .accessibilityIdentifier("settings-about-licenses-sheet")
  }
}
