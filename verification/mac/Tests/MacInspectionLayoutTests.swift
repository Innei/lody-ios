import AppKit
import XCTest
@testable import LodyMacApp

@MainActor
final class MacInspectionLayoutTests: XCTestCase {
  func testWindowNavigationKeepsASeparateStableGapBesideTheSidebarButton() throws {
    let window = try XCTUnwrap(MacInspectionFixture.windows(width: 1440).first)
    defer { window.close() }
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    var gaps: [CGFloat] = []
    for width: CGFloat in [1440, 760, 1440] {
      window.setContentSize(NSSize(width: width, height: 820))
      window.layoutIfNeeded(); window.contentView?.superview?.layoutSubtreeIfNeeded()
      let views = descendants(try XCTUnwrap(window.contentView?.superview))
      let navigation = try XCTUnwrap(views.first { $0.accessibilityIdentifier() == "session-navigation" })
      let navigationRect = navigation.convert(navigation.bounds, to: nil)
      let sidebarRect = try XCTUnwrap(views.compactMap { $0 as? NSButton }.map { $0.convert($0.bounds, to: nil) }
        .filter { $0.minX > navigationRect.maxX && abs($0.midY - navigationRect.midY) < 1 && $0.height >= 28 }
        .min { $0.minX < $1.minX })
      let gap = sidebarRect.minX - navigationRect.maxX
      XCTAssertGreaterThanOrEqual(gap, 11, "Keep the 12 pt group gap, allowing AppKit's 1 pt content outset")
      XCTAssertLessThanOrEqual(gap, 16, "Spacing belongs to the leading group, not the toolbar's empty-item padding")
      gaps.append(gap)
    }
    XCTAssertEqual(try XCTUnwrap(gaps.max()), try XCTUnwrap(gaps.min()), accuracy: 1)
  }
  func testMinimumWindowKeepsConversationAndFileVisibleWithoutGrowing() throws {
    let window = try XCTUnwrap(MacInspectionFixture.windows(width: 760).first)
    defer { window.close() }
    window.layoutIfNeeded(); window.contentView?.layoutSubtreeIfNeeded()
    let workspace = try XCTUnwrap(window.contentViewController as? MacWorkspaceController)
    XCTAssertEqual(window.contentView?.bounds.width ?? 0, 760, accuracy: 2)
    XCTAssertGreaterThanOrEqual(workspace.splitViewItems[1].viewController.view.bounds.width, 420)
    XCTAssertGreaterThanOrEqual(workspace.splitViewItems[2].viewController.view.bounds.width, 320)
    workspace.toggleInspection(nil)
    XCTAssertFalse(workspace.splitViewItems[0].isCollapsed)
  }
  func testOpeningThePanelKeepsTheWindowAndConversationAtTheirApprovedWidths() throws {
    let window = try XCTUnwrap(MacInspectionFixture.windows().first)
    defer { window.close() }
    window.layoutIfNeeded(); window.contentView?.layoutSubtreeIfNeeded()
    let workspace = try XCTUnwrap(window.contentViewController as? MacWorkspaceController)
    XCTAssertEqual(window.contentView?.bounds.width ?? 0, 1100, accuracy: 2)
    XCTAssertTrue(workspace.splitViewItems[0].isCollapsed)
    XCTAssertGreaterThanOrEqual(workspace.splitViewItems[1].viewController.view.bounds.width, 420)
    XCTAssertEqual(workspace.splitViewItems[2].viewController.view.bounds.width, 620, accuracy: 2)
  }
  func testFileTabsUseTheNativeTitlebarInsteadOfAddingAnotherContentRow() throws {
    let window = try XCTUnwrap(MacInspectionFixture.windows().first)
    defer { window.close() }
    window.layoutIfNeeded(); window.contentView?.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let titlebarViews = window.titlebarAccessoryViewControllers.flatMap { descendants($0.view) }
    let changes = try XCTUnwrap(titlebarViews.first { $0.accessibilityIdentifier() == "inspection-changes-tab" })
    let rect = changes.convert(changes.bounds, to: nil)
    XCTAssertGreaterThan(rect.minY, window.frame.height - 64, "File navigation must share the window chrome")
    let workspace = try XCTUnwrap(window.contentViewController as? MacWorkspaceController)
    let panel = workspace.splitViewItems[2].viewController.view
    let range = try XCTUnwrap(descendants(panel).first { $0.accessibilityIdentifier() == "inspection-range" })
    XCTAssertLessThan(abs(range.convert(range.bounds, to: nil).midY - rect.midY), 66, "A second header must not push Diff down")
  }

  func testNarrowFileStripKeepsTheSelectedTabAndCloseButtonReachableAfterResize() throws {
    let tabs = MacInspectionTabs(frame: NSRect(x: 0, y: 0, width: 520, height: 52))
    var state = MacInspectionState()
    for index in 0..<6 { state.show(.file("Sources/LongDocumentName\(index).swift"), pinned: true) }
    tabs.render(state)
    tabs.layoutSubtreeIfNeeded()
    tabs.setFrameSize(NSSize(width: 218, height: 52))
    tabs.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let views = descendants(tabs)
    let scroll = try XCTUnwrap(views.compactMap { $0 as? NSScrollView }.first)
    let selected = try XCTUnwrap(views.first { $0.accessibilityIdentifier() == "inspection-tab-Sources/LongDocumentName5.swift" })
    let close = try XCTUnwrap(views.first { $0.accessibilityIdentifier() == "inspection-close-Sources/LongDocumentName5.swift" } as? NSButton)
    let selectedRect = selected.convert(selected.bounds, to: scroll.contentView)
    XCTAssertGreaterThanOrEqual(selectedRect.minX, scroll.contentView.bounds.minX - 1)
    XCTAssertLessThanOrEqual(selectedRect.maxX, scroll.contentView.bounds.maxX + 1)
    let closeRect = close.convert(close.bounds, to: scroll.contentView)
    XCTAssertGreaterThanOrEqual(closeRect.minX, scroll.contentView.bounds.minX - 1)
    XCTAssertLessThanOrEqual(closeRect.maxX, scroll.contentView.bounds.maxX + 1)
    XCTAssertFalse(close.isHiddenOrHasHiddenAncestor)
    var closed: MacInspectionTarget?
    tabs.close = { closed = $0 }
    close.performClick(nil)
    XCTAssertEqual(closed, .file("Sources/LongDocumentName5.swift"))
  }

}
