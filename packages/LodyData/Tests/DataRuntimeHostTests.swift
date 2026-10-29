import XCTest
import LodyData

@MainActor
final class DataRuntimeHostTests: XCTestCase {
  final class FakeHost: LodyHost {
    var isActive = false
    var isBackground = true
    var catalogs: [String] = []
    func open(_ url: URL) async -> Bool { true }
    func copyLink(_ url: URL) {}
    func beginSendAllowance(expired: @escaping @MainActor () -> Void) -> AnyObject? { nil }
    func endSendAllowance(_ token: AnyObject) {}
    func toast(_ message: String, kind: String) {}
    func alert(title: String, message: String) {}
    func presentAuthorization(_ url: URL) -> Bool { false }
    func dismissAuthorization() {}
    func catalogDidUpdate(_ catalogJSON: String, workspaceId: String, workspaceSlug: String, workspaceName: String, userId: String) {
      catalogs.append(catalogJSON)
    }
    func clearSharedData() {}
    func forgetDevice() {}
  }

  private func store() -> LocalStore {
    LocalStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("lody-\(UUID().uuidString).sqlite"))
  }

  func testRuntimeStartedInBackgroundWaitsWithoutAWebView() {
    let host = FakeHost()
    LodyHosting.current = host
    defer { LodyHosting.current = nil }
    let runtime = DataRuntime(localStore: store())
    var states: [String] = []
    runtime.onCatalogUpdate = { _, state, _ in states.append(state) }
    runtime.start(workspace: "w", slug: "team", name: "Team", owner: "owner", userId: "user")
    XCTAssertEqual(states, ["background"])
  }

  func testLocalStoreRoundTripsOnMac() throws {
    let local = store()
    try local.write("account", #"{"user":"u"}"#)
    XCTAssertEqual(try local.read("account"), #"{"user":"u"}"#)
  }
}
