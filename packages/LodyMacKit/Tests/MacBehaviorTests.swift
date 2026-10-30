import AppKit
import XCTest
import LodyData
@testable import LodyMacKit

final class MacAccentTests: XCTestCase {
  func testAccentChoicesFollowTheSystemAndNeverOfferGreenOrRed() {
    XCTAssertEqual(MacAccent.allCases.map(\.rawValue), ["system", "blue", "purple", "orange", "graphite"])
    for name in [NSAppearance.Name.aqua, .darkAqua] {
      NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
        let red = Self.hue(.systemRed)!
        let green = Self.hue(.systemGreen)!
        for accent in MacAccent.allCases where accent != .system {
          guard let hue = Self.hue(accent.color) else { continue }
          XCTAssertGreaterThan(Self.distance(hue, green), 30, "\(accent) reads as green in \(name.rawValue)")
          XCTAssertGreaterThan(Self.distance(hue, red), 12, "\(accent) reads as red in \(name.rawValue)")
        }
      }
    }
  }

  private static func hue(_ color: NSColor) -> Double? {
    guard let color = color.usingColorSpace(.sRGB), color.saturationComponent > 0.15 else { return nil }
    return color.hueComponent * 360
  }

  private static func distance(_ a: Double, _ b: Double) -> Double {
    let d = abs(a - b).truncatingRemainder(dividingBy: 360)
    return min(d, 360 - d)
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
