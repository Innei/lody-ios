import AppKit
import LodyData
import XCTest
@testable import LodyMacKit

@MainActor
final class MacSettingsPolishTests: XCTestCase {
  private let lab = AuthWorkspace(id: "w-lab", name: "Lab", slug: "lab", image: nil)

  private var chosen = MacAccent.system

  private func model() -> MacSettingsModel {
    let user = AuthUser(id: "u", name: "Innei", email: "i@innei.dev", image: nil)
    let state = SettingsState(account: AuthAccount(user: user, workspaces: [lab]), workspace: lab)
    let source = SettingsSource(changes: [], read: { state }, refresh: {}, logout: {})
    let defaults = UserDefaults(suiteName: "lody-mac-settings-polish-\(UUID().uuidString)")!
    var services = MacSettingsServices(source: source, selectWorkspace: { _ in }, signIn: {})
    services.appearance = MacAppearanceServices(
      theme: { .system }, setTheme: { _ in },
      accent: { [unowned self] in chosen }, setAccent: { [unowned self] in chosen = $0 },
      reading: { .standard }, setReading: { _ in }
    )
    return MacSettingsModel(services: services, defaults: defaults)
  }

  func testTheSidebarDropsTheAccentHighlightForTheNeutralGrey() throws {
    let window = try XCTUnwrap(MacSettingsWindow.make(model: model()).window)
    defer { window.close() }
    window.layoutIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    let tables = tables(in: try XCTUnwrap(window.contentView))
    let sidebar = try XCTUnwrap(tables.first { $0.numberOfRows > 0 && $0.selectedRow >= 0 })
    XCTAssertEqual(sidebar.selectionHighlightStyle, .none)
  }

  func testSettingsFollowTheLodyAccent() {
    let model = model()
    XCTAssertEqual(model.accent, .system)
    chosen = .purple
    NotificationCenter.default.post(name: .lodyMacAccentDidChange, object: nil)
    XCTAssertEqual(model.accent, .purple)
  }

  private func tables(in view: NSView) -> [NSTableView] {
    (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables(in:))
  }
}
