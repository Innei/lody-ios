import AppKit
import ChatAppKit
import ChatKitCore
import LodyData
import XCTest
@testable import LodyMacApp

final class MacRecordingMedia: CKMediaProvider, @unchecked Sendable {
  private let lock = NSLock()
  private var sizes: [CGSize] = []

  var requested: [CGSize] { lock.withLock { sizes } }

  func image(for ref: CKMediaRef, pixelSize: CGSize) async throws -> CGImage {
    lock.withLock { sizes.append(pixelSize) }
    return MacFixtureMedia.swatch(seed: ref.id, size: CGSize(width: 64, height: 48))
  }

  func fileURL(for ref: CKMediaRef) async throws -> URL {
    URL(fileURLWithPath: "/tmp/\(ref.id)")
  }
}

@MainActor
final class MacTranscriptMediaTests: XCTestCase {
  private func host(_ media: CKMediaProvider) -> (MacTranscriptView, NSWindow) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let transcript = MacTranscriptView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    transcript.media = media
    window.contentView = transcript
    return (transcript, window)
  }

  func testAnImageRowLoadsItsThumbnailAtTheCellsPixelSize() throws {
    let media = MacRecordingMedia()
    let (transcript, window) = host(media)
    defer { window.close() }
    let json = """
    [{"id":"a1","role":"assistant","status":"completed","finished":true,"items":[{"itemId":"i","type":"image","image":{"id":"img-1","fileName":"chart.png","width":800,"height":600}}]}]
    """
    transcript.render(MacTranscriptModel(entriesJSON: json))
    window.layoutIfNeeded()
    let image = try XCTUnwrap(transcript.descendants(MacTranscriptImageView.self).first)
    let loaded = expectation(description: "thumbnail")
    Task { @MainActor in
      while image.photo.image == nil { try? await Task.sleep(for: .milliseconds(10)) }
      loaded.fulfill()
    }
    wait(for: [loaded], timeout: 3)
    let scale = window.backingScaleFactor
    XCTAssertEqual(image.photo.bounds.width, MacTranscriptImageView.maxWidth)
    XCTAssertEqual(media.requested.last?.width, image.photo.bounds.width * scale)
    XCTAssertEqual(media.requested.last?.height, image.photo.bounds.height * scale)
    XCTAssertEqual(image.accessibilityLabel(), "chart.png")
  }

  func testADoubleClickOnAnImagePreviewsOnce() throws {
    var previewed = 0
    let view = MacTranscriptImageView(media: CKMediaRef(id: "img"), name: "chart.png", aspect: 1, provider: nil)
    view.frame = NSRect(x: 0, y: 0, width: 400, height: 320)
    view.layoutSubtreeIfNeeded()
    view.onPreview = { _ in previewed += 1 }
    let up = { (count: Int) in
      NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 10, y: 300), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: count, pressure: 0)!
    }
    view.mouseUp(with: up(1))
    view.mouseUp(with: up(2))
    XCTAssertEqual(previewed, 1)
  }

  func testPressingAnImageOrAPillAsksToPreviewItsMedia() throws {
    let (transcript, window) = host(MacRecordingMedia())
    defer { window.close() }
    var previewed: [String] = []
    transcript.onPreview = { previewed.append($0.id) }
    let json = """
    [{"id":"a1","role":"assistant","status":"completed","finished":true,"items":[{"itemId":"i","type":"image","image":{"id":"img-1","fileName":"chart.png"}}]}]
    """
    let pending = """
    {"id":"p1","text":"","status":"sending","attachments":[{"id":"f1","name":"notes.txt","uri":"file:///tmp/notes.txt","kind":"file"}]}
    """
    transcript.render(MacTranscriptModel(entriesJSON: json, pendingJSON: pending))
    window.layoutIfNeeded()
    _ = try XCTUnwrap(transcript.descendants(MacTranscriptImageView.self).first).accessibilityPerformPress()
    _ = try XCTUnwrap(transcript.descendants(CKAttachmentStripView.self).first).pills[0].accessibilityPerformPress()
    XCTAssertEqual(previewed, ["img-1", "f1"])
  }

  func testPendingAttachmentsShowOnePillPerFileWithUploadProgress() throws {
    let (transcript, window) = host(MacRecordingMedia())
    defer { window.close() }
    let pending = """
    {"id":"p1","text":"","status":"sending","attachments":[
      {"id":"f1","name":"notes.txt","uri":"file:///tmp/notes.txt","kind":"file"},
      {"id":"f2","name":"shot.png","uri":"file:///tmp/shot.png","kind":"image"}],
     "uploadProgress":{"f1":{"phase":"uploading","percent":40},"f2":{"phase":"complete","percent":100}}}
    """
    transcript.render(MacTranscriptModel(entriesJSON: "[]", pendingJSON: pending))
    window.layoutIfNeeded()
    let strip = try XCTUnwrap(transcript.descendants(CKAttachmentStripView.self).first)
    XCTAssertEqual(strip.pills.map(\.attachment.name), ["notes.txt", "shot.png"])
    XCTAssertEqual(strip.pills[0].progress?.doubleValue, 40)
    XCTAssertNil(strip.pills[1].progress)
    XCTAssertTrue(strip.pills[0].accessibilityLabel()?.hasPrefix("notes.txt, ") == true)
    XCTAssertTrue(strip.pills.allSatisfy { $0.removeButton == nil })
  }
}

@MainActor
final class MacTranscriptAttachmentReuseTests: XCTestCase {
  func testUploadProgressKeepsTheRowAndItsThumbnails() throws {
    let media = MacRecordingMedia()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let transcript = MacTranscriptView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
    transcript.media = media
    window.contentView = transcript
    func render(_ percent: Int) {
      let pending = """
      {"id":"p1","text":"","status":"sending","attachments":[{"id":"f2","name":"shot.png","uri":"file:///tmp/shot.png","kind":"image"}],
       "uploadProgress":{"f2":{"phase":"uploading","percent":\(percent)}}}
      """
      transcript.render(MacTranscriptModel(entriesJSON: "[]", pendingJSON: pending))
      window.layoutIfNeeded()
    }
    render(10)
    let first = try XCTUnwrap(transcript.descendants(MacTranscriptAttachmentsView.self).first)
    let loaded = expectation(description: "thumbnail")
    Task { @MainActor in
      while first.strip.pills.first?.attachment.thumbnail == nil { try? await Task.sleep(for: .milliseconds(10)) }
      loaded.fulfill()
    }
    wait(for: [loaded], timeout: 3)
    let requests = media.requested.count
    render(60)
    let second = try XCTUnwrap(transcript.descendants(MacTranscriptAttachmentsView.self).first)
    XCTAssertTrue(first === second)
    XCTAssertNotNil(second.strip.pills.first?.attachment.thumbnail)
    XCTAssertEqual(second.strip.pills.first?.progress?.doubleValue, 60)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    XCTAssertEqual(media.requested.count, requests)
  }
}

final class MacTranscriptRunningTurnTests: XCTestCase {
  func testARunningTurnThatInterleavesNarrationAndToolsHasUniqueRows() {
    let json = """
    [{"id":"u1","role":"user","status":"completed","finished":true,"items":[{"itemId":"q","type":"text","text":"Go"}]},
     {"id":"a1","role":"assistant","status":"in_progress","finished":false,"items":[
      {"itemId":"read","type":"tool_call","kind":"read","title":"Read A.swift","status":"completed"},
      {"itemId":"intro","type":"text","text":"Reading first."},
      {"itemId":"edit","type":"tool_call","kind":"edit","title":"Edit A.swift","status":"completed"},
      {"itemId":"mid","type":"text","text":"Now building."},
      {"itemId":"build","type":"tool_call","kind":"execute","title":"Build","status":"in_progress"}]}]
    """
    let ids = MacTranscriptModel(entriesJSON: json).items.map(\.id)
    XCTAssertEqual(ids.count, Set(ids).count, "duplicate rows: \(ids)")
    XCTAssertTrue(ids.contains("a1:mid"))
  }
}
