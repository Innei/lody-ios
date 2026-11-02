import AppKit
import XCTest
import LodyData
import LodyCore
@testable import LodyMacApp

@MainActor
final class MacInspectionTests: XCTestCase {
  func testClosingALoadingFileAllowsItToBeOpenedAgain() async {
    var release: CheckedContinuation<MacInspectionContent, Error>?
    var reads = 0
    let model = MacInspectionModel(service: .init(diff: { _, _ in .init(handle: "test", oldKind: "text", newKind: "text") }, changes: { .init(base: "main", files: []) }, read: { _ in
      reads += 1
      if reads == 1 { return try await withCheckedThrowingContinuation { release = $0 } }
      return .stored("reopened")
    }, directory: { _ in .init(entries: [], truncated: false) }))
    model.show(.file("slow.swift"))
    for _ in 0..<20 where release == nil { await Task.yield() }
    model.state.close(.file("slow.swift"))
    release?.resume(returning: .stored("old"))
    await model.waitForLoads()
    XCTAssertNil(model.documents[.file("slow.swift")]?.value)
    model.show(.file("slow.swift"))
    await model.waitForLoads()
    XCTAssertEqual(reads, 2)
    XCTAssertEqual(model.documents[.file("slow.swift")]?.value, .stored("reopened"))
  }
  func testFilePreviewUsesReadonlyNativeTextInsteadOfTheLoadingPlaceholder() async throws {
    let handle = ContentStore.shared.put(.init(data: Data("let answer = 42\n".utf8), kind: "text", path: "Answer.swift", session: "test", mimeType: nil))
    let model = MacInspectionModel(service: .init(diff: { _, _ in .init(handle: "test", oldKind: "text", newKind: "text") }, changes: { .init(base: "main", files: []) }, read: { _ in .stored(handle) }, directory: { _ in .init(entries: [], truncated: false) }))
    let controller = MacInspectionController()
    controller.bind(model)
    model.show(.file("Answer.swift"))
    await model.waitForLoads()
    func texts(_ view: NSView) -> [NSTextView] { (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(texts) }
    let text = try XCTUnwrap(texts(controller.view).first)
    XCTAssertEqual(text.string, "let answer = 42\n")
    XCTAssertFalse(text.isEditable)
    XCTAssertTrue(text.isSelectable)
  }
  func testTurnScopeLoadsOnlyExpandedFilesAndPreservesEntryIdentity() async throws {
    var requests: [(String, String?)] = []
    let model = MacInspectionModel(service: .init(diff: { path, entry in
      requests.append((path, entry))
      return .init(handle: "test", oldKind: "text", newKind: "text")
    }, changes: { .init(base: "feature-base", files: []) }, read: { _ in .stored("test") }, directory: { _ in .init(entries: [], truncated: false) }))
    model.showChanges(entry: .init(id: "old-turn", title: "Yesterday", files: [.init(path: "a.swift"), .init(path: "b.swift")]))
    await model.waitForLoads()
    XCTAssertEqual(requests.map(\.0), ["a.swift"])
    XCTAssertEqual(requests.first?.1, "old-turn")
    model.toggleDiff("b.swift")
    await model.waitForLoads()
    XCTAssertEqual(requests.map(\.0), ["a.swift", "b.swift"])
  }

  func testSupersededScopeCannotAcceptAnOlderDiffResult() async {
    var release: CheckedContinuation<MacInspectionDiff, Error>?
    let model = MacInspectionModel(service: .init(diff: { _, _ in
      try await withCheckedThrowingContinuation { release = $0 }
    }, changes: { .init(base: "main", files: []) }, read: { _ in .stored("test") }, directory: { _ in .init(entries: [], truncated: false) }))
    model.showChanges(entry: .init(id: "old", title: "Old", files: [.init(path: "a.swift")]))
    for _ in 0..<20 where release == nil { await Task.yield() }
    model.suspend()
    release?.resume(returning: .init(handle: "stale", oldKind: "text", newKind: "text"))
    await model.waitForLoads()
    XCTAssertNil(model.diffs["a.swift"]?.value)
  }

  func testRefreshingAFailedFileKeepsItsPreviousContent() async {
    var fail = false
    let model = MacInspectionModel(service: .init(diff: { _, _ in .init(handle: "test", oldKind: "text", newKind: "text") }, changes: { .init(base: "main", files: []) }, read: { _ in
      if fail { throw NSError(domain: "offline", code: 1) }
      return .stored("first")
    }, directory: { _ in .init(entries: [], truncated: false) }))
    model.show(.file("a.swift"))
    await model.waitForLoads()
    fail = true
    model.refresh()
    await model.waitForLoads()
    XCTAssertEqual(model.documents[.file("a.swift")]?.value, .stored("first"))
    XCTAssertNotNil(model.documents[.file("a.swift")]?.error)
  }

  func testDirectoriesAreLazyAndTruncationRemainsVisible() async {
    var reads: [String] = []
    let model = MacInspectionModel(service: .init(diff: { _, _ in .init(handle: "test", oldKind: "text", newKind: "text") }, changes: { .init(base: "main", files: []) }, read: { _ in .stored("test") }, directory: { path in
      reads.append(path)
      return .init(entries: [.init(name: "Sources", directory: true)], truncated: true)
    }))
    XCTAssertTrue(reads.isEmpty)
    model.loadDirectory("")
    await model.waitForLoads()
    XCTAssertEqual(reads, [""])
    XCTAssertEqual(model.directories[""]?.value?.truncated, true)
  }
  func testFilteringChangedFilesDoesNotChangeTheComparisonOrFetchHiddenFiles() async throws {
    var requests: [String] = []
    let model = MacInspectionModel(service: .init(diff: { path, _ in requests.append(path); return .init(handle: "test", oldKind: "text", newKind: "text") }, changes: { .init(base: "main", files: []) }, read: { _ in .stored("test") }, directory: { _ in .init(entries: [], truncated: false) }))
    let controller = MacInspectionController(); controller.bind(model)
    controller.view.frame = NSRect(x: 0, y: 0, width: 640, height: 600)
    model.showChanges(entry: .init(id: "reply", title: "Yesterday", files: [.init(path: "a.swift", add: 4, del: 2), .init(path: "docs/b.md", add: 1, del: 0)]))
    await model.waitForLoads()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let search = try XCTUnwrap(descendants(controller.view).first { $0.accessibilityIdentifier() == "inspection-change-filter" } as? NSSearchField)
    search.stringValue = "b.md"
    search.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: search))
    controller.view.layoutSubtreeIfNeeded()
    let table = try XCTUnwrap(descendants(controller.view).compactMap { $0 as? NSTableView }.first)
    XCTAssertEqual(table.numberOfRows, 1)
    XCTAssertEqual(model.turn?.id, "reply")
    XCTAssertEqual(requests, ["a.swift"])
    search.stringValue = ""
    search.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: search))
    XCTAssertGreaterThan(table.numberOfRows, 1)
  }

  func testFilePopoverRemainsInspectableWhenOpenedFromTheNativePreviewToolbar() async throws {
    let window = try XCTUnwrap(MacInspectionFixture.windows().first)
    defer { window.close() }
    window.orderFront(nil); window.layoutIfNeeded()
    let workspace = try XCTUnwrap(window.contentViewController as? MacWorkspaceController)
    let controller = try XCTUnwrap(workspace.splitViewItems[2].viewController as? MacInspectionController)
    let model = try XCTUnwrap(controller.model)
    model.show(.file("macOS/Views/Composer/MacComposerView.swift"))
    await model.waitForLoads(); window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertNil(MacVerifyActions.perform(.click("inspection-files"), in: window))
    await model.waitForLoads(); window.contentView?.layoutSubtreeIfNeeded()
    let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: out) }
    try MacViewDump.write(to: out)
    let dump = try String(contentsOf: out, encoding: .utf8)
    XCTAssertTrue(dump.contains("inspection-file-filter"))
  }

  func testOpeningCodeKeepsItsFirstCharacterVisibleBesideTheLineRuler() async throws {
    let window = try XCTUnwrap(MacInspectionFixture.windows().first)
    defer { window.close() }
    window.orderFront(nil)
    let workspace = try XCTUnwrap(window.contentViewController as? MacWorkspaceController)
    let controller = try XCTUnwrap(workspace.splitViewItems[2].viewController as? MacInspectionController)
    let model = try XCTUnwrap(controller.model)
    model.show(.file("macOS/Views/Composer/MacComposerView.swift")); await model.waitForLoads()
    window.contentView?.layoutSubtreeIfNeeded()
    func texts(_ view: NSView) -> [NSTextView] { (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(texts) }
    let text = try XCTUnwrap(texts(controller.view).first)
    let manager = try XCTUnwrap(text.layoutManager), container = try XCTUnwrap(text.textContainer)
    let ruler = try XCTUnwrap(text.enclosingScrollView?.verticalRulerView)
    manager.ensureLayout(for: container)
    var first = manager.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: container)
    first.origin.x += text.textContainerOrigin.x; first.origin.y += text.textContainerOrigin.y
    let glyphRect = text.convert(first, to: controller.view), rulerRect = ruler.convert(ruler.bounds, to: controller.view)
    XCTAssertGreaterThanOrEqual(glyphRect.minX, rulerRect.maxX, "The ruler must not cover the first glyph")
  }

  func testLongDiffOffersTheRemainingHunksWithoutAnotherMachineRead() async throws {
    let old = (1...80).map { "line \($0)" }.joined(separator: "\n")
    let new = old.replacingOccurrences(of: "line 5\n", with: "changed 5\n").replacingOccurrences(of: "line 35\n", with: "changed 35\n").replacingOccurrences(of: "line 65\n", with: "changed 65\n")
    let result = RuntimeContract.DiffResultOk(base: .turn, path: "file.swift", old: .init(kind: .text, text: old), new: .init(kind: .text, text: new))
    let handle = ContentStore.shared.put(.init(data: try JSONEncoder().encode(result), kind: "diff", path: "file.swift", session: "test", mimeType: nil))
    var reads = 0
    let model = MacInspectionModel(service: .init(diff: { _, _ in reads += 1; return .init(handle: handle, oldKind: "text", newKind: "text") }, changes: { .init(base: "main", files: []) }, read: { _ in .stored(handle) }, directory: { _ in .init(entries: [], truncated: false) }))
    model.showChanges(entry: .init(id: "reply", title: "Reply", files: [.init(path: "file.swift")]))
    await model.waitForLoads()
    let view = MacDiffView(frame: NSRect(x: 0, y: 0, width: 620, height: 1000)); view.render(model); view.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let table = try XCTUnwrap(descendants(view).compactMap { $0 as? NSTableView }.first)
    let before = table.numberOfRows
    let button = try XCTUnwrap(descendants(view).compactMap { $0 as? NSButton }.first { $0.accessibilityIdentifier() == "inspection-more-hunks-file.swift" })
    button.performClick(nil)
    XCTAssertGreaterThan(table.numberOfRows, before)
    XCTAssertEqual(reads, 1)
  }

}
