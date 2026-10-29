import AppKit
import XCTest
import LodyData
@testable import LodyMacKit

final class MacAccentTests: XCTestCase {
  func testAccentChoicesFollowTheSystemAndNeverOfferGreenOrRed() {
    XCTAssertEqual(MacAccent.allCases.map(\.rawValue), ["system", "blue", "purple", "pink", "orange", "graphite"])
    for accent in MacAccent.allCases where accent != .system {
      guard let color = accent.color.usingColorSpace(.sRGB), color.saturationComponent > 0.15 else { continue }
      let hue = color.hueComponent * 360
      XCTAssertFalse((80...170).contains(hue), "\(accent) reads as green")
      XCTAssertFalse(hue < 12 || hue > 348, "\(accent) reads as red")
    }
  }

  func testTheChoiceIsStoredAndUnknownValuesFallBackToSystem() {
    let defaults = UserDefaults(suiteName: "lody-mac-accent-\(UUID().uuidString)")!
    XCTAssertEqual(MacAccent.current(defaults), .system)
    MacAccent.purple.save(defaults)
    XCTAssertEqual(MacAccent.current(defaults), .purple)
    defaults.set("green", forKey: MacAccent.key)
    XCTAssertEqual(MacAccent.current(defaults), .system)
  }
}

@MainActor
final class MacNotificationDecisionTests: XCTestCase {
  private func catalog(_ sessions: [SessionItem]) -> SessionCatalog { SessionCatalog(sessions: sessions) }

  func testPermissionRequestsAndFinishedRepliesNotifyWhenOffScreen() {
    let before = catalog([
      SessionItem(id: "a", title: "Build", status: "running"),
      SessionItem(id: "b", title: "Docs", status: "running"),
    ])
    let after = catalog([
      SessionItem(id: "a", title: "Build", status: "idle"),
      SessionItem(id: "b", title: "Docs", status: "running", awaitingUserSince: 10),
    ])
    let decisions = MacNotificationDecider.decide(previous: before, next: after, onScreen: nil)
    XCTAssertEqual(decisions, [.finished(sessionId: "a", title: "Build"), .permission(sessionId: "b", title: "Docs")])
  }

  func testTheSessionOnScreenAndUnchangedSessionsStayQuiet() {
    let before = catalog([SessionItem(id: "a", status: "running"), SessionItem(id: "c", status: "idle")])
    let after = catalog([SessionItem(id: "a", status: "idle"), SessionItem(id: "c", status: "idle")])
    XCTAssertEqual(MacNotificationDecider.decide(previous: before, next: after, onScreen: "a"), [])
    XCTAssertEqual(MacNotificationDecider.decide(previous: nil, next: after, onScreen: nil), [])
  }
}
