import LodyData
import XCTest
@testable import LodyMacApp

@MainActor
final class MacAboutSettingsTests: XCTestCase {
  private var records = 3
  private var exported: [TimeInterval] = []
  private var saved: [URL] = []

  private func model() -> MacAboutModel {
    MacAboutModel(services: MacAboutServices(
      version: { ("1.2", "45") },
      licenses: { .empty },
      launched: { 600 },
      count: { _ in self.records },
      export: { window in
        self.exported.append(window)
        return URL(fileURLWithPath: "/tmp/diagnostics.txt")
      },
      clear: { self.records = 0 },
      save: { self.saved.append($0) }
    ))
  }

  func testDiagnosticsCountSinceLaunch() async {
    let model = model()
    await model.refresh()
    XCTAssertEqual(model.count, 3)
    XCTAssertEqual(model.version, "1.2 (45)")
  }

  func testExportSavesTheFileForTheLaunchWindow() async {
    let model = model()
    await model.export()
    XCTAssertEqual(exported, [600])
    XCTAssertEqual(saved.map(\.lastPathComponent), ["diagnostics.txt"])
  }

  func testClearEmptiesTheCount() async {
    let model = model()
    await model.refresh()
    await model.clear()
    XCTAssertEqual(model.count, 0)
  }
}
