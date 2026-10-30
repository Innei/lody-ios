import AppKit
import LodyData
import Metal
import XCTest
@testable import LodyMacKit

@MainActor
final class MacSignInTests: XCTestCase {
  func testJellyfishShaderCompilesWithBothStages() throws {
    guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("no Metal device") }
    let library = try device.makeLibrary(source: MacJellyfishShader.source, options: nil)
    XCTAssertNotNil(library.makeFunction(name: MacJellyfishShader.vertex))
    XCTAssertNotNil(library.makeFunction(name: MacJellyfishShader.fragment))
  }

  func testRevealDevelopsOverItsDurationAndIsWholeUnderReduceMotion() {
    let motion = MacJellyfishMotion(reduceMotion: false)
    XCTAssertEqual(motion.reveal(elapsed: 0), 0)
    XCTAssertEqual(motion.reveal(elapsed: MacJellyfishMotion.revealDuration / 2), 0.5, accuracy: 0.001)
    XCTAssertEqual(motion.reveal(elapsed: 10), 1)
    XCTAssertEqual(MacJellyfishMotion(reduceMotion: true).reveal(elapsed: 0), 1)
  }

  func testLeaveRunsForOneSecondAndIsSkippedUnderReduceMotion() {
    let motion = MacJellyfishMotion(reduceMotion: false)
    XCTAssertEqual(motion.leave(elapsed: nil), 0)
    XCTAssertEqual(motion.leave(elapsed: 0.5), 0.5, accuracy: 0.001)
    XCTAssertEqual(motion.leave(elapsed: 3), 1)
    XCTAssertEqual(MacJellyfishMotion.leaveDuration, 1)
    XCTAssertEqual(MacJellyfishMotion(reduceMotion: true).leaveDuration, 0)
  }

  func testTheGridIsWholeThreePointCells() {
    let grid = MacJellyfishMotion.grid(for: NSSize(width: 464, height: 544))
    XCTAssertEqual(grid.columns, 154)
    XCTAssertEqual(grid.rows, 181)
    XCTAssertEqual(MacJellyfishMotion.grid(for: .zero).columns, 1)
  }

  func testExpiryRoundsUpToWholeMinutesAndReportsExpiry() {
    XCTAssertEqual(MacSignInCopy.minutesLeft(599), 10)
    XCTAssertEqual(MacSignInCopy.minutesLeft(61), 2)
    XCTAssertEqual(MacSignInCopy.minutesLeft(1), 1)
    XCTAssertNil(MacSignInCopy.minutesLeft(0))
  }

  func testLegalLinksFollowTheLanguage() {
    XCTAssertEqual(MacSignInCopy.legalURL("terms", language: "zh-Hans").absoluteString, "https://lody.ai/zh/terms")
    XCTAssertEqual(MacSignInCopy.legalURL("privacy", language: "en").absoluteString, "https://lody.ai/privacy")
  }

  func testOnboardingChromeIsFixedDarkAndRestoresTheWorkspaceFrame() {
    let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 1100, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.toolbar = NSToolbar(identifier: "test")
    let before = window.frame
    let saved = MacOnboardingChrome.enter(window)
    XCTAssertEqual(window.frame.size, MacOnboardingChrome.size)
    XCTAssertEqual(window.frame.midX, before.midX, accuracy: 1)
    XCTAssertFalse(window.styleMask.contains(.resizable))
    XCTAssertTrue(window.titlebarAppearsTransparent)
    XCTAssertEqual(window.toolbar?.isVisible, false)
    XCTAssertEqual(window.appearance?.name, .darkAqua)

    MacOnboardingChrome.leave(window, restoring: saved)
    XCTAssertEqual(window.frame, before)
    XCTAssertTrue(window.styleMask.contains(.resizable))
    XCTAssertFalse(window.titlebarAppearsTransparent)
    XCTAssertEqual(window.toolbar?.isVisible, true)
    XCTAssertNil(window.appearance)
  }

  func testEnteringTwiceKeepsTheFirstSavedFrame() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                          styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    let before = window.frame
    let saved = MacOnboardingChrome.enter(window)
    XCTAssertEqual(MacOnboardingChrome.enter(window, keeping: saved).frame, before)
  }

  func testWelcomeTurnsIntoTheCodeWithACopyButton() async throws {
    var copied: [String] = []
    var service = SignInService.fixture(code: nil)
    service.copy = { copied.append($0) }
    let controller = SignInViewController(service: service)
    let root = controller.view
    XCTAssertTrue(texts(root).contains(String(localized: "mac.signIn.welcome", bundle: .lodyMac)))
    XCTAssertNotNil(visible(root, "sign-in-legal"))
    XCTAssertNil(visible(root, "sign-in-code"))

    (visible(root, "sign-in-primary") as? NSButton)?.performClick(nil)
    try await until { self.visible(root, "sign-in-code") != nil }
    XCTAssertEqual((visible(root, "sign-in-code") as? NSTextField)?.stringValue, "WXYZ-1234")
    XCTAssertTrue(texts(root).contains(String(localized: "mac.signIn.confirm", bundle: .lodyMac)))
    XCTAssertNil(visible(root, "sign-in-legal"))
    (visible(root, "sign-in-copy") as? NSButton)?.performClick(nil)
    XCTAssertEqual(copied, ["WXYZ-1234"])

    (visible(root, "sign-in-cancel") as? NSButton)?.performClick(nil)
    try await until { self.visible(root, "sign-in-code") == nil }
  }

  private func until(_ condition: () -> Bool) async throws {
    for _ in 0..<50 where !condition() { try await Task.sleep(for: .milliseconds(20)) }
    XCTAssertTrue(condition())
  }

  func testFinishingNamesTheUserAndCallsBackAfterTheJellyfishLeaves() {
    let controller = SignInViewController(service: .fixture(code: "WXYZ-1234"), motion: MacJellyfishMotion(reduceMotion: true))
    _ = controller.view
    let done = expectation(description: "finished")
    controller.finish(name: "Innei") { done.fulfill() }
    XCTAssertTrue(texts(controller.view).contains(String(format: String(localized: "mac.signIn.done", bundle: .lodyMac), "Innei")))
    XCTAssertNil(visible(controller.view, "sign-in-code"))
    wait(for: [done], timeout: 1)
  }

  private func texts(_ view: NSView) -> [String] {
    var out: [String] = []
    walk(view) { if let field = $0 as? NSTextField { out.append(field.stringValue) } }
    return out
  }

  private func visible(_ view: NSView, _ identifier: String) -> NSView? {
    var found: NSView?
    walk(view) { if found == nil, $0.accessibilityIdentifier() == identifier { found = $0 } }
    return found
  }

  private func walk(_ view: NSView, _ body: (NSView) -> Void) {
    guard !view.isHidden else { return }
    body(view)
    for child in view.subviews { walk(child, body) }
  }
}

@MainActor
final class MacOnboardingWindowTests: XCTestCase {
  func testSignedOutWindowIsTheOnboardingWindowAndSignInSwimsIntoTheWorkspace() async throws {
    let changes = Notification.Name("MacOnboardingWindowTests.auth")
    var account: AuthAccount?
    let sessions = MacSessionsSource.fixture(MacFixtures.listState)
    var environment = MacEnvironment(
      sessions: sessions, pane: { MacSessionSummaryPane(sessionId: $0, sessions: sessions) }, newSession: { MacPlaceholderController(text: "") }
    )
    environment.windowIdentifier = "onboarding-test"
    environment.account = { account }
    environment.authChanges = changes
    environment.signIn = { SignInViewController(service: .fixture(code: nil), motion: MacJellyfishMotion(reduceMotion: true)) }
    let controller = MainWindowController(environment: environment)
    let window = try XCTUnwrap(controller.window)
    defer { window.close() }
    XCTAssertTrue(window.contentViewController is SignInViewController)
    XCTAssertEqual(window.frame.size, MacOnboardingChrome.size)
    XCTAssertEqual(window.appearance?.name, .darkAqua)
    XCTAssertNil(controller.workspace)

    account = AuthAccount(user: AuthUser(id: "u", name: "Innei", email: "i@innei.dev", image: nil), workspaces: [])
    NotificationCenter.default.post(name: changes, object: nil)
    for _ in 0..<50 where controller.workspace == nil { try await Task.sleep(for: .milliseconds(20)) }
    XCTAssertNotNil(controller.workspace)
    XCTAssertTrue(window.contentViewController is MacWorkspaceController)
    XCTAssertEqual(window.frame.size, NSSize(width: 1100, height: 720))
    XCTAssertTrue(window.styleMask.contains(.resizable))
    XCTAssertNil(window.appearance)
  }
}
