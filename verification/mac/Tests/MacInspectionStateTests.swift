import XCTest
#if canImport(LodyMacApp)
@testable import LodyMacApp
#endif

final class MacInspectionStateTests: XCTestCase {
  func testTemporaryPreviewReplacesOnlyTheUnpinnedFile() {
    var state = MacInspectionState()
    state.show(.file("Sources/A.swift"))
    state.pin(.file("Sources/A.swift"))
    state.show(.file("Sources/B.swift"))
    state.show(.file("Sources/C.swift"))
    XCTAssertEqual(state.tabs.map(\.target), [.file("Sources/A.swift"), .file("Sources/C.swift")])
    XCTAssertEqual(state.selection, .document(.file("Sources/C.swift")))
    state.show(.file("Sources/A.swift"))
    XCTAssertEqual(state.tabs.count, 2)
    XCTAssertTrue(state.tabs[0].pinned)
  }

  func testClosingUsesLeftNeighborAndCannotCloseChanges() {
    var state = MacInspectionState()
    state.show(.file("A"), pinned: true)
    state.show(.file("B"), pinned: true)
    state.show(.file("C"), pinned: true)
    state.close(.file("B"))
    XCTAssertEqual(state.selection, .document(.file("C")))
    state.close(.file("C"))
    XCTAssertEqual(state.selection, .document(.file("A")))
    state.close(.file("A"))
    XCTAssertEqual(state.selection, .changes)
    XCTAssertTrue(state.tabs.isEmpty)
  }

  func testFullPathsAndAttachmentSourceSessionsRemainDistinct() {
    var state = MacInspectionState()
    state.show(.file("a/index.swift"), pinned: true)
    state.show(.file("b/index.swift"), pinned: true)
    state.show(.attachment(id: "same", session: "one", name: "picture.png"), pinned: true)
    state.show(.attachment(id: "same", session: "two", name: "picture.png"), pinned: true)
    XCTAssertEqual(state.tabs.count, 4)
  }

  func testCompactLayoutKeepsConversationAndRestoresOnlyAutomaticSidebarCollapse() {
    var layout = MacInspectionLayout()
    layout.isOpen = true
    let compact = layout.resolve(width: 1100)
    XCTAssertTrue(compact.sidebarHidden)
    XCTAssertFalse(compact.chatHidden)
    XCTAssertEqual(compact.panelWidth, 620, accuracy: 1)
    layout.isOpen = false
    XCTAssertFalse(layout.resolve(width: 1100).sidebarHidden)
    layout.userSidebarHidden = true
    XCTAssertTrue(layout.resolve(width: 1100).sidebarHidden)
  }

  func testSmallestWindowAndExpandDoNotDestroyPreferredWidth() {
    var layout = MacInspectionLayout()
    layout.isOpen = true
    layout.preferredWidth = 640
    let small = layout.resolve(width: 760)
    XCTAssertGreaterThanOrEqual(small.panelWidth, 320)
    XCTAssertGreaterThanOrEqual(760 - small.panelWidth, 420)
    layout.expanded = true
    XCTAssertTrue(layout.resolve(width: 1100).chatHidden)
    layout.expanded = false
    XCTAssertEqual(layout.resolve(width: 1440).panelWidth, 640)
    XCTAssertFalse(layout.resolve(width: 1440).sidebarHidden)
  }
}
