import AppKit
import LodyData
import XCTest
@testable import LodyMacKit

@MainActor
final class MacThemeTests: XCTestCase {
  private func defaults() -> UserDefaults {
    UserDefaults(suiteName: "lody-mac-theme-\(UUID().uuidString)")!
  }

  func testThemeIsSavedPerMacAndDefaultsToFollowSystem() {
    let defaults = defaults()
    XCTAssertEqual(MacTheme.current(defaults), .system)
    MacTheme.dark.save(defaults)
    XCTAssertEqual(MacTheme.current(defaults), .dark)
    defaults.set("sepia", forKey: MacTheme.key)
    XCTAssertEqual(MacTheme.current(defaults), .system)
  }

  func testApplyingAThemeSetsTheAppAppearance() {
    defer { NSApp.appearance = nil }
    MacTheme.dark.apply(defaults())
    XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
    MacTheme.light.apply(defaults())
    XCTAssertEqual(NSApp.appearance?.name, .aqua)
    MacTheme.system.apply(defaults())
    XCTAssertNil(NSApp.appearance)
  }
}

@MainActor
final class MacReadingTests: XCTestCase {
  func testReadingDefaultsAndClampsTheTextSize() {
    let defaults = UserDefaults(suiteName: "lody-mac-reading-\(UUID().uuidString)")!
    XCTAssertEqual(MacReading.current(defaults), MacReading(textSize: 13, fillWidth: false))
    MacReading(textSize: 30, fillWidth: true).save(defaults)
    XCTAssertEqual(MacReading.current(defaults), MacReading(textSize: 18, fillWidth: true))
    MacReading(textSize: 4, fillWidth: false).save(defaults)
    XCTAssertEqual(MacReading.current(defaults).textSize, 11)
  }

  private func transcript(width: CGFloat) -> (MacTranscriptView, NSView) {
    let view = MacTranscriptView()
    view.translatesAutoresizingMaskIntoConstraints = false
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
    let root = NSView()
    window.contentView = root
    root.addSubview(view)
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      view.topAnchor.constraint(equalTo: root.topAnchor),
      view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    var model = MacTranscriptModel(entriesJSON: "[]")
    model.items = [.user(id: "u", text: "Hi"), .prose(id: "p", markdown: "Hello there")]
    view.render(model)
    root.layoutSubtreeIfNeeded()
    return (view, root)
  }

  func testFillWidthLiftsTheTranscriptWidthCap() throws {
    let (view, root) = transcript(width: 1400)
    let prose = try XCTUnwrap(view.rowViews.last)
    XCTAssertLessThanOrEqual(prose.frame.width, 780)
    view.reading = MacReading(textSize: 13, fillWidth: true)
    root.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(prose.frame.width, 1300)
  }

  func testTextSizeReachesProseAndUserBubbles() throws {
    let (view, _) = transcript(width: 800)
    view.reading = MacReading(textSize: 16, fillWidth: false)
    let prose = try XCTUnwrap(view.rowViews.compactMap { $0 as? MacMarkdownView }.first)
    XCTAssertEqual(prose.bodyFont.pointSize, 16)
    let user = try XCTUnwrap(view.rowViews.first as? MacUserTurnView)
    XCTAssertEqual(user.descendants(NSTextField.self).first?.font?.pointSize, 16)
  }

  func testTextSizeReachesTheComposerInput() {
    let composer = MacComposerView(frame: NSRect(x: 0, y: 0, width: 400, height: 120))
    composer.reading = MacReading(textSize: 15, fillWidth: false)
    XCTAssertEqual(composer.input.font?.pointSize, 15)
  }

  func testFillWidthLiftsTheComposerWidthCap() {
    let composer = NSViewController()
    composer.view = NSView()
    let source = MacTranscriptSource(start: { _ in }, stop: {}, detail: { _ in nil }, respond: { _, _ in .accepted })
    let controller = MacSessionController(sessionId: "s", source: source, composer: composer)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
    window.contentViewController = controller
    window.setContentSize(NSSize(width: 1400, height: 600))
    controller.view.layoutSubtreeIfNeeded()
    XCTAssertLessThanOrEqual(composer.view.frame.width, 780)
    controller.reading = MacReading(textSize: 13, fillWidth: true)
    controller.view.layoutSubtreeIfNeeded()
    XCTAssertGreaterThan(composer.view.frame.width, 1300)
  }
}

@MainActor
final class MacAppearanceModelTests: XCTestCase {
  func testChoicesSaveThroughTheirServices() {
    var theme = MacTheme.system
    var accent = MacAccent.system
    var reading = MacReading(textSize: 13, fillWidth: false)
    let model = MacAppearanceModel(services: MacAppearanceServices(
      theme: { theme }, setTheme: { theme = $0 },
      accent: { accent }, setAccent: { accent = $0 },
      reading: { reading }, setReading: { reading = $0 }
    ))
    model.theme = .dark
    model.accent = .orange
    model.textSize = 15
    model.fillWidth = true
    XCTAssertEqual(theme, .dark)
    XCTAssertEqual(accent, .orange)
    XCTAssertEqual(reading, MacReading(textSize: 15, fillWidth: true))
    XCTAssertEqual(model.theme, .dark)
  }
}
