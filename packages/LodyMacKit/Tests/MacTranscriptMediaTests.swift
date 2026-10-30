import AppKit
import ChatAppKit
import ChatKitCore
import LodyData
import XCTest
@testable import LodyMacKit

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
