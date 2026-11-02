import AppKit
import Quartz
import PDFKit
import XCTest
import LodyData
import LodyCore
import ChatKitCore
@testable import LodyMacApp

@MainActor
final class MacInspectionReviewTests: XCTestCase {
  private func service(changes: @escaping @MainActor () async throws -> MacInspectionChanges = { .init(base: "main", files: []) }) -> MacInspectionService {
    .init(diff: { _, _ in .init(handle: "test", oldKind: "text", newKind: "text") }, changes: changes, read: { _ in .stored("test") }, directory: { _ in .init(entries: [], truncated: false) })
  }

  func testWorkspaceFailureCannotRelabelHistoricalFilesAsCurrentChanges() async {
    let model = MacInspectionModel(service: service(changes: { throw NSError(domain: "offline", code: 1) }))
    model.showChanges(entry: .init(id: "old", title: "Yesterday", files: [.init(path: "historical.swift")]))
    await model.waitForLoads()
    model.showChanges(entry: nil)
    await model.waitForLoads()
    XCTAssertTrue(model.files.isEmpty)
    XCTAssertTrue(model.base.isEmpty)
    XCTAssertNotNil(model.changesError)
  }

  func testOwnedDownloadsAreReleasedWhenTheirLastPreviewClosesButLocalFilesSurvive() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("owned")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let owned = directory.appendingPathComponent("owned.txt"); try Data("owned".utf8).write(to: owned)
    let borrowed = root.appendingPathComponent("borrowed.txt"); try Data("local".utf8).write(to: borrowed)
    let model = MacInspectionModel(service: service())
    let controller = MacInspectionController(); controller.bind(model)
    let target = MacInspectionTarget.attachment(id: "remote", session: "s", name: "owned.txt")
    model.showAttachment(target) { .owned(MacPreviewLease(url: owned, directory: directory)) }
    await model.waitForLoads()
    XCTAssertTrue(FileManager.default.fileExists(atPath: owned.path))
    model.closeDocument(target)
    XCTAssertFalse(FileManager.default.fileExists(atPath: owned.path))
    let local = MacInspectionTarget.attachment(id: "local", session: "s", name: "borrowed.txt")
    model.showAttachment(local) { try await MacMediaProvider(workspace: "w", session: "s").previewFile(for: CKMediaRef(id: "local", context: ["local": borrowed.absoluteString])) }
    await model.waitForLoads()
    model.closeDocument(local)
    XCTAssertTrue(FileManager.default.fileExists(atPath: borrowed.path))
  }

  func testRestoringExpandedFilesBoundsSimultaneousMachineRequests() async {
    var active = 0, maximum = 0, requests = 0
    var source = service()
    source.diff = { _, _ in
      active += 1; requests += 1; maximum = max(maximum, active)
      try await Task.sleep(for: .milliseconds(20))
      active -= 1
      return .init(handle: "test", oldKind: "text", newKind: "text")
    }
    let model = MacInspectionModel(service: source)
    let files = (0..<12).map { MacInspectionFile(path: "file-\($0).swift") }
    model.showChanges(entry: .init(id: "reply", title: "Reply", files: files))
    for file in files.dropFirst() { model.toggleDiff(file.path) }
    await model.waitForLoads()
    XCTAssertEqual(requests, 12)
    XCTAssertLessThanOrEqual(maximum, 4)
  }

  func testAWaitingSessionDoesNotReadUntilItsExistingRuntimeBecomesReady() async {
    var ready = false, reads = 0
    var source = service()
    source.ready = { ready }; source.read = { _ in reads += 1; return .stored("ready") }
    let model = MacInspectionModel(service: source)
    model.show(.file("file.swift"))
    await model.waitForLoads()
    XCTAssertEqual(reads, 0)
    ready = true; model.resumeIfReady()
    await model.waitForLoads()
    XCTAssertEqual(reads, 1)
  }

  func testLongDiffLineCanBeScrolledToItsEnd() async throws {
    let long = String(repeating: "A", count: 6000)
    let result = RuntimeContract.DiffResultOk(base: .turn, path: "long.txt", old: .init(kind: .text, text: "short"), new: .init(kind: .text, text: long))
    let handle = ContentStore.shared.put(.init(data: try JSONEncoder().encode(result), kind: "diff", path: "long.txt", session: "s", mimeType: nil))
    var source = service(); source.diff = { _, _ in .init(handle: handle, oldKind: "text", newKind: "text") }
    let model = MacInspectionModel(service: source)
    model.showChanges(entry: .init(id: "reply", title: "Reply", files: [.init(path: "long.txt")]))
    await model.waitForLoads()
    let view = MacDiffView(frame: NSRect(x: 0, y: 0, width: 620, height: 500)); view.render(model)
    func tables(_ view: NSView) -> [NSTableView] { (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap(tables) }
    let table = try XCTUnwrap(tables(view).first)
    let needed = (long as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)]).width
    XCTAssertGreaterThan(table.tableColumns[0].width, needed)
  }

  func testRestoringInterruptedWorkspaceChangesStartsARealListLoad() async {
    var first: CheckedContinuation<MacInspectionChanges, Error>?
    var reads = 0
    let model = MacInspectionModel(service: service(changes: {
      reads += 1
      if reads == 1 { return try await withCheckedThrowingContinuation { first = $0 } }
      return .init(base: "feature", files: [.init(path: "current.swift")])
    }))
    model.showChanges(entry: nil)
    for _ in 0..<30 where first == nil { await Task.yield() }
    model.suspend()
    first?.resume(returning: .init(base: "old", files: []))
    model.resumeIfReady()
    await model.waitForLoads()
    XCTAssertEqual(reads, 2)
    XCTAssertEqual(model.files.map(\.path), ["current.swift"])
  }

  func testTranscriptKeepsSummaryAndOpensTheClickedFile() async throws {
    let json = #"[{"id":"reply","role":"assistant","status":"completed","finished":true,"items":[],"fileDiffs":[{"path":"a.swift","add":1,"del":1},{"path":"b.swift","add":1,"del":1}]}]"#
    let projection = MacTranscriptModel(entriesJSON: json)
    XCTAssertEqual(projection.items.filter { $0.kind == "changes" }.count, 3, "summary plus both file rows")
    let model = MacInspectionModel(service: service())
    let pane = MacSessionController(sessionId: "s", source: .init(start: { $0(.init(status: "live", entriesJSON: json)) }, stop: {}, detail: { _ in nil }, respond: { _, _ in .accepted }))
    pane.inspectionModel = model
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = pane
    defer { window.close() }
    pane.setStreaming(true); pane.view.layoutSubtreeIfNeeded()
    let transcript = try XCTUnwrap(pane.view.subviews.compactMap { $0 as? MacTranscriptView }.first)
    let rows = transcript.rowViews
    func buttons(_ view: NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
    let button = try XCTUnwrap(rows.flatMap(buttons).first { $0.title.contains("b.swift") })
    button.performClick(nil)
    await model.waitForLoads()
    XCTAssertTrue(model.expanded.contains("b.swift"))
    XCTAssertFalse(model.expanded.contains("a.swift"))
    XCTAssertEqual(model.turn?.id, "reply")
  }

  func testNativeTabDeactivationStopsInspectionReads() async throws {
    let window = try XCTUnwrap(MacInspectionFixture.windows().first)
    defer { window.close() }
    let workspace = try XCTUnwrap(window.contentViewController as? MacWorkspaceController)
    let inspection = try XCTUnwrap(workspace.splitViewItems[2].viewController as? MacInspectionController)
    let model = try XCTUnwrap(inspection.model)
    model.show(.file("slow.swift"))
    workspace.setStreaming(false)
    await model.waitForLoads()
    XCTAssertTrue(model.documents.isEmpty)
  }

  func testWorkspaceAndAttachmentPDFsUseQuickLookBeforeTextOrImageSniffing() async throws {
    let bytes = Self.pdf()
    XCTAssertEqual(PDFDocument(data: bytes)?.pageCount, 2)
    XCTAssertNotNil(String(data: bytes, encoding: .utf8))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("two-pages.pdf"); try bytes.write(to: url)
    let handle = ContentStore.shared.put(.init(data: bytes, kind: "binary", path: "two-pages.pdf", session: "test", mimeType: "application/pdf"))
    let model = MacInspectionModel(service: service())
    func quickLooks(_ view: NSView) -> [QLPreviewView] { (view as? QLPreviewView).map { [$0] } ?? view.subviews.flatMap(quickLooks) }
    for content in [MacInspectionContent.stored(handle), .url(url)] {
      let preview = MacFilePreviewView(target: .file("two-pages.pdf"), content: content, model: model)
      XCTAssertEqual(quickLooks(preview).count, 1)
    }
  }

  func testQuickLookCanCloseAfterItsFileTabMovesOutOfTheWindow() async throws {
    let handle = ContentStore.shared.put(.init(data: Self.pdf(), kind: "binary", path: "two-pages.pdf", session: "test", mimeType: "application/pdf"))
    var source = service(); source.read = { _ in .stored(handle) }
    let model = MacInspectionModel(service: source)
    let controller = MacInspectionController(); controller.bind(model)
    let window = MacOffscreenWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentViewController = controller
    defer { window.close() }
    model.show(.file("two-pages.pdf"))
    await model.waitForLoads()
    controller.view.layoutSubtreeIfNeeded()
    model.select(.changes)
    await model.waitForLoads()
    model.closeDocument(.file("two-pages.pdf"))
    XCTAssertTrue(model.state.tabs.isEmpty)
  }

  private static func pdf() -> Data {
    let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>"]
    var text = "%PDF-1.4\n", offsets: [Int] = [0]
    for (i, object) in objects.enumerated() { offsets.append(text.utf8.count); text += "\(i + 1) 0 obj\n\(object)\nendobj\n" }
    let xref = text.utf8.count
    text += "xref\n0 5\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { text += String(format: "%010d 00000 n \n", offset) }
    text += "trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
    return Data(text.utf8)
  }
}
