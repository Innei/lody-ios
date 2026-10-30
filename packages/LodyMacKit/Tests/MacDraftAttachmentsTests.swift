import AppKit
import ChatAppKit
import LodyData
import XCTest
@testable import LodyMacKit

final class MacDraftAttachmentsTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("draft-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func file(_ name: String, bytes: Int = 12) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try Data(repeating: 65, count: bytes).write(to: url)
    return url
  }

  func testAddingAFileCopiesItIntoATemporaryDraftItem() throws {
    var draft = MacDraftAttachments()
    let source = try file("notes.txt")
    XCTAssertTrue(draft.add(urls: [source]).isEmpty)
    let item = try XCTUnwrap(draft.items.first)
    XCTAssertEqual(item.name, "notes.txt")
    XCTAssertFalse(item.isImage)
    XCTAssertNotEqual(item.url, source)
    XCTAssertTrue(item.url.path.hasPrefix(FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path) || item.url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    XCTAssertEqual(Set(draft.payload.first?.keys ?? [:].keys), ["id", "name", "uri", "kind"])
    XCTAssertEqual(draft.payload.first?["kind"] as? String, "file")
    XCTAssertEqual(draft.payload.first?["uri"] as? String, item.url.absoluteString)
  }

  func testLimitsAndUnsupportedFilesAreRejected() throws {
    var draft = MacDraftAttachments(maxBytes: 100)
    let images = try (0..<9).map { try file("shot-\($0).png") }
    XCTAssertEqual(draft.add(urls: images), [.tooMany])
    XCTAssertEqual(draft.items.count, 8)
    XCTAssertEqual(draft.add(urls: [folder]), [.unsupported(folder.lastPathComponent)])
    XCTAssertEqual(draft.add(urls: [try file("page.webarchive")]), [.unsupported("page.webarchive")])
    XCTAssertEqual(draft.add(urls: [try file("empty.txt", bytes: 0)]), [.unsupported("empty.txt")])
    XCTAssertEqual(draft.add(urls: [try file("big.bin", bytes: 101)]), [.tooLarge("big.bin")])
    XCTAssertEqual(draft.items.count, 8)
  }

  func testPastedImagesBecomeTemporaryImageFiles() throws {
    var draft = MacDraftAttachments()
    let board = NSPasteboard(name: .init("lody-tests-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    board.clearContents()
    let image = NSImage(size: NSSize(width: 4, height: 4))
    image.lockFocus()
    NSColor.systemPink.setFill()
    NSRect(x: 0, y: 0, width: 4, height: 4).fill()
    image.unlockFocus()
    board.writeObjects([image])
    XCTAssertEqual(draft.add(pasteboard: board), [])
    let item = try XCTUnwrap(draft.items.first)
    XCTAssertTrue(item.isImage)
    XCTAssertEqual(item.url.pathExtension, "png")
    XCTAssertTrue(FileManager.default.fileExists(atPath: item.url.path))
  }

  func testPlainTextOnThePasteboardIsNotAnAttachment() {
    var draft = MacDraftAttachments()
    let board = NSPasteboard(name: .init("lody-tests-\(UUID().uuidString)"))
    defer { board.releaseGlobally() }
    board.clearContents()
    board.setString("hello", forType: .string)
    XCTAssertNil(draft.add(pasteboard: board))
  }
}

@MainActor
final class MacComposerAttachmentTests: XCTestCase {
  func testASendCarriesAttachmentsAndAFailureRestoresThem() throws {
    final class Sent { var payloads: [[String: Any]] = [] }
    let sent = Sent()
    var model = MacComposerModel(mode: .reply)
    model.replyReady = true
    let controller = MacComposerController(model: model, service: MacComposerService(
      options: { _, _ in throw OutboxError.scopeExpired }, create: { _, _ in },
      reply: { payload, _ in sent.payloads.append(payload) }
    ))
    let source = FileManager.default.temporaryDirectory.appendingPathComponent("composer-\(UUID().uuidString).txt")
    try Data("x".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }
    controller.addFiles([source])
    let strip = try XCTUnwrap(controller.view.descendants(CKAttachmentStripView.self).first)
    XCTAssertEqual(strip.pills.count, 1)
    XCTAssertTrue(strip.pills[0].removeButton != nil)
    let input = try XCTUnwrap(controller.view.descendants(MacComposerTextView.self).first)
    input.onSubmit?()
    XCTAssertEqual((sent.payloads.first?["attachments"] as? [[String: Any]])?.count, 1)
    XCTAssertTrue(strip.pills.isEmpty)
    controller.restoreDraft()
    XCTAssertEqual(strip.pills.map(\.attachment.name), [source.lastPathComponent])
  }

  func testFilesDroppedOnTheTranscriptJoinTheReplyDraft() throws {
    let composer = MacComposerController(model: MacComposerModel(mode: .reply), service: MacComposerService(
      options: { _, _ in throw OutboxError.scopeExpired }, create: { _, _ in }
    ))
    let source = MacTranscriptSource(start: { _ in }, stop: {}, detail: { _ in nil }, respond: { _, _ in .accepted })
    let pane = MacSessionController(sessionId: "s", source: source, composer: composer)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString).txt")
    try Data("x".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let transcript = try XCTUnwrap(pane.view.descendants(MacTranscriptView.self).first)
    transcript.dropFiles([file])
    XCTAssertEqual(composer.model.attachments.items.map(\.name), [file.lastPathComponent])
  }

  func testRejectedFilesExplainWhyInTheComposer() throws {
    let controller = MacComposerController(model: MacComposerModel(mode: .reply), service: MacComposerService(
      options: { _, _ in throw OutboxError.scopeExpired }, create: { _, _ in }
    ))
    controller.addFiles([FileManager.default.temporaryDirectory])
    let notice = try XCTUnwrap(controller.view.descendants(NSTextField.self).first { $0.accessibilityIdentifier() == "composer-notice" })
    XCTAssertFalse(notice.isHidden)
    XCTAssertEqual(notice.stringValue, String(localized: "mac.attachments.unsupported \(FileManager.default.temporaryDirectory.lastPathComponent)", bundle: .lodyMac))
  }
}
