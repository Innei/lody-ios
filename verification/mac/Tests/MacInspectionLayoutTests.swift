import AppKit
import XCTest
@testable import LodyMacApp

@MainActor
final class MacInspectionLayoutTests: XCTestCase {
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

}
