import AppKit
import XCTest
import LodyCore
import LodyData
@testable import LodyMacApp

@MainActor
final class MacDiffTests: XCTestCase {
  func testATurnChangesSummaryOpensTheCorrectEntryAndFiles() throws {
    var model = MacTranscriptModel(entriesJSON: "[]")
    model.items = [.changes(id: "change-one", text: "Sources/App.swift +2 −1")]
    model.groups = ["change-one": "turn-one"]
    let files = [MacChangedFile(path: "Sources/App.swift", add: 2, del: 1)]
    model.changedFiles = ["turn-one": files]
    let transcript = MacTranscriptView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
    let window = NSWindow(contentRect: transcript.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = transcript
    var selected: (String, [MacChangedFile])?
    transcript.onChanges = { selected = ($0, $1) }
    transcript.render(model)
    transcript.layoutSubtreeIfNeeded()
    _ = transcript.rowViews
    let button = try XCTUnwrap(transcript.descendants(NSButton.self).first { $0.accessibilityIdentifier() == "transcript-changes" })
    button.performClick(nil)
    XCTAssertEqual(selected?.0, "turn-one")
    XCTAssertEqual(selected?.1, files)
  }

  func testTurnAndSessionRequestsRenderActualPatchAndFinalNewline() async {
    var requests: [MacDiffRequest] = []
    let service = MacDiffService(diff: { request in
      requests.append(request)
      return Self.result(request.path, old: "before\n", new: "after")
    }, changes: { id in
      XCTAssertEqual(id, "session")
      return .ok(.init(base: "main", files: [.init(path: "All.swift", add: 1, del: 1)]))
    })
    let model = MacDiffModel(sessionId: "session", entryId: "turn", files: [.init(path: "Turn.swift")], service: service)
    await model.load()
    XCTAssertEqual(requests.first, .init(sessionId: "session", entryId: "turn", path: "Turn.swift"))
    XCTAssertTrue(model.patch.contains("-before\n+after\n\\ No newline at end of file"), model.patch)
    await model.setScope(.session)
    XCTAssertEqual(requests.last, .init(sessionId: "session", entryId: nil, path: "All.swift"))
    XCTAssertEqual(model.base, "main")
  }

  func testFailureCanRetryAndBinaryLargeEmptyAndUnavailableHaveVisibleStates() async {
    var attempt = 0
    let service = MacDiffService(diff: { request in
      attempt += 1
      if attempt == 1 { throw OutboxError.scopeExpired }
      switch request.path {
      case "binary": return .ok(.init(base: .turn, path: request.path, old: .init(kind: .binary), new: .init(kind: .binary)))
      case "large": return .ok(.init(base: .turn, path: request.path, old: .init(kind: .tooLarge), new: .init(kind: .text, text: "new")))
      case "wrong-path": return Self.result("another-path", old: "private", new: "wrong")
      case "same": return Self.result(request.path, old: "same", new: "same")
      default: return Self.result(request.path, old: "old", new: "new")
      }
    }, changes: { _ in .ok(.init(base: "main", files: [])) })
    let model = MacDiffModel(sessionId: "s", entryId: "e", files: ["text", "binary", "large", "wrong-path", "same"].map { .init(path: $0) }, service: service)
    await model.load()
    XCTAssertFalse(model.message.isEmpty)
    XCTAssertTrue(model.patch.isEmpty)
    await model.load()
    XCTAssertTrue(model.patch.contains("+new"))
    for path in ["binary", "large", "wrong-path", "same"] {
      await model.select(path)
      XCTAssertTrue(model.patch.isEmpty, path)
      XCTAssertFalse(model.message.isEmpty, path)
    }
    await model.setScope(.session)
    XCTAssertTrue(model.files.isEmpty)
    XCTAssertFalse(model.message.isEmpty)
  }

  func testLateFileResponseDoesNotReplaceCurrentSelection() async {
    var waiting: CheckedContinuation<RuntimeContract.DiffResult, Never>?
    let service = MacDiffService(diff: { request in
      if request.path == "slow" { return await withCheckedContinuation { waiting = $0 } }
      return Self.result(request.path, old: "old", new: "latest")
    }, changes: { _ in .ok(.init(base: "main", files: [])) })
    let model = MacDiffModel(sessionId: "s", entryId: "e", files: [.init(path: "slow"), .init(path: "fast")], service: service)
    let first = Task { await model.load() }
    while waiting == nil { await Task.yield() }
    await model.select("fast")
    waiting?.resume(returning: Self.result("slow", old: "old", new: "stale"))
    await first.value
    XCTAssertEqual(model.selectedPath, "fast")
    XCTAssertTrue(model.patch.contains("+latest"))
    XCTAssertFalse(model.patch.contains("stale"))
  }

  private static func result(_ path: String, old: String, new: String) -> RuntimeContract.DiffResult {
    .ok(.init(base: .turn, path: path, old: .init(kind: .text, text: old), new: .init(kind: .text, text: new)))
  }
}
