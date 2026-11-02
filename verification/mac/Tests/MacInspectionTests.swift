import AppKit
import XCTest
import LodyData
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
}
