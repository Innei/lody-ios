import Foundation
import ImageIO
import PhotosUI
import QuickLook
import UIKit
import UniformTypeIdentifiers

#if !canImport(ExpoModulesCore)
// The standalone check only records the production bridge's completion result.
@MainActor
final class Promise {
  var value: Any?
  var error: Error?
  var resolved = false
  var resolutions = 0
  func resolve(_ value: Any?) { self.value = value; resolved = true; resolutions += 1 }
  func reject(_ error: Error) { self.error = error }
}
#endif

@MainActor
final class PickerHost: UIViewController {
  var captured: UIViewController?
  override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
    captured = viewControllerToPresent
    completion?()
  }
}

func check(_ condition: Bool, _ message: String) {
  if !condition { fatalError(message) }
}

@MainActor
func run() throws {
  let raw = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
  defer { try? FileManager.default.removeItem(at: raw) }
  let format = UIGraphicsImageRendererFormat()
  format.scale = 1
  let image = UIGraphicsImageRenderer(size: CGSize(width: 380, height: 800), format: format).image { context in
    UIColor.systemBlue.setFill()
    context.fill(CGRect(x: 0, y: 0, width: 380, height: 800))
  }
  let bytes = NSMutableData()
  let destination = CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image.cgImage!, [
    kCGImagePropertyOrientation: 6,
    kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "synthetic-private-metadata"],
    kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.345, kCGImagePropertyGPSLatitudeRef: "N"],
  ] as CFDictionary)
  check(CGImageDestinationFinalize(destination), "metadata fixture writes")
  try (bytes as Data).write(to: raw)
  let normalized = try BugFeedback.imageData(raw)
  let screenshot = try BugFeedback.store(normalized)
  defer { try? FileManager.default.removeItem(at: screenshot) }
  let source = CGImageSourceCreateWithURL(screenshot as CFURL, nil)!
  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
  check(properties[kCGImagePropertyGPSDictionary] == nil, "GPS metadata must not enter reports")
  check(!(properties.description.contains("synthetic-private-metadata")), "EXIF private metadata must not enter reports")
  check((properties[kCGImagePropertyPixelWidth] as? Int) == 800 && (properties[kCGImagePropertyPixelHeight] as? Int) == 380,
    "image orientation is preserved while metadata is stripped")
  let details = try BugFeedback.details(screenshot)
  check(details["type"] as? String == "image/png" && (details["size"] as? Int) == normalized.count, "image export describes actual bytes")
  check(try BugFeedback.ownedURL(screenshot.absoluteString) == screenshot, "the app can preview its own screenshot")

  let privateFile = FileManager.default.temporaryDirectory.appendingPathComponent("private-\(UUID().uuidString).txt")
  let privateContents = Data("synthetic-private-file".utf8)
  try privateContents.write(to: privateFile)
  defer { try? FileManager.default.removeItem(at: privateFile) }
  let malicious = [
    privateFile.absoluteString,
    "https://private.invalid/Screenshot-test.png",
    screenshot.deletingLastPathComponent().appendingPathComponent("../Screenshot-test.png").absoluteString,
  ]
  for uri in malicious {
    do { _ = try BugFeedback.ownedURL(uri); fatalError("foreign path accepted: \(uri)") }
    catch { }
    let result = Promise()
    BugFeedback().screenshot(command: "remove", uri: uri, from: nil, promise: result)
    check(result.error != nil, "foreign screenshot removal is rejected")
  }
  let link = screenshot.deletingLastPathComponent().appendingPathComponent("Screenshot-symlink.png")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: privateFile)
  defer { try? FileManager.default.removeItem(at: link) }
  do { _ = try BugFeedback.ownedURL(link.absoluteString); fatalError("symlink accepted") }
  catch { }
  check(try Data(contentsOf: privateFile) == privateContents, "rejected actions preserve foreign files")

  let previewHost = PickerHost()
  let previewed = Promise()
  BugFeedback().screenshot(command: "preview", uri: screenshot.absoluteString, from: previewHost, promise: previewed)
  guard let navigation = previewHost.captured as? UINavigationController,
    let preview = navigation.viewControllers.first as? QLPreviewController else {
    fatalError("screenshot preview must present the system navigation controls")
  }
  preview.loadViewIfNeeded()
  check(!previewed.resolved, "the form waits while the screenshot is open")
  let editedBytes = NSMutableData()
  let editedDestination = CGImageDestinationCreateWithData(editedBytes, UTType.jpeg.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(editedDestination, image.cgImage!, [
    kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "synthetic-private-edited-metadata"],
    kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.345, kCGImagePropertyGPSLatitudeRef: "N"],
  ] as CFDictionary)
  check(CGImageDestinationFinalize(editedDestination), "edited-copy metadata fixture writes")
  try (editedBytes as Data).write(to: raw)
  preview.delegate?.previewController?(preview, didSaveEditedCopyOf: screenshot as NSURL, at: raw)
  let savedSource = CGImageSourceCreateWithURL(screenshot as CFURL, nil)!
  let savedProperties = CGImageSourceCopyPropertiesAtIndex(savedSource, 0, nil)! as NSDictionary
  check((savedProperties[kCGImagePropertyPixelWidth] as? Int) == 380 && (savedProperties[kCGImagePropertyPixelHeight] as? Int) == 800,
    "Quick Look's saved-copy callback replaces the selected screenshot with the user's edited copy")
  check(CGImageSourceGetType(savedSource) as String? == UTType.png.identifier
    && savedProperties[kCGImagePropertyGPSDictionary] == nil
    && !savedProperties.description.contains("synthetic-private-edited-metadata"),
    "edited copies are normalized to PNG without private image metadata")
  preview.delegate?.previewControllerDidDismiss?(preview)
  check(previewed.resolved && previewed.error == nil, "closing Quick Look settles the form action with the selected image")
  preview.delegate?.previewControllerDidDismiss?(preview)
  check(previewed.resolutions == 1, "duplicate Quick Look close notifications settle the action once")

  let invalid = try BugFeedback.store(Data("not an image".utf8))
  defer { try? FileManager.default.removeItem(at: invalid) }
  do { _ = try BugFeedback.details(invalid); fatalError("non-image screenshot accepted") }
  catch { }
  let removed = Promise()
  BugFeedback().screenshot(command: "remove", uri: screenshot.absoluteString, from: nil, promise: removed)
  check(removed.error == nil && !FileManager.default.fileExists(atPath: screenshot.path), "removing a selected screenshot only deletes its app copy")
  let environment = BugFeedback.environment()
  check(environment["systemVersion"]?.isEmpty == false && environment["deviceModel"]?.isEmpty == false, "system supplies the device environment")
  check(Set(environment.keys).isSubset(of: ["version", "build", "systemVersion", "deviceModel"]), "environment does not expose other process or bundle configuration")
  let picker = BugFeedback()
  let host = PickerHost()
  let cancelled = Promise()
  picker.screenshot(command: "pick", uri: "", from: host, promise: cancelled)
  let firstPicker = host.captured!
  picker.presentationControllerDidDismiss(UIPresentationController(presentedViewController: firstPicker, presenting: host))
  check(cancelled.resolved && cancelled.value == nil && cancelled.error == nil, "interactive picker cancellation settles without selecting an image")
  let reopened = Promise()
  picker.screenshot(command: "pick", uri: "", from: host, promise: reopened)
  check(reopened.error == nil && !reopened.resolved, "a cancelled picker can open again")
  picker.presentationControllerDidDismiss(UIPresentationController(presentedViewController: firstPicker, presenting: host))
  check(!reopened.resolved, "an old picker dismissal cannot cancel a new picker")
  picker.presentationControllerDidDismiss(UIPresentationController(presentedViewController: host.captured!, presenting: host))
  check(reopened.resolved, "the new picker settles its own cancellation")
  print("PASS: feedback screenshot metadata, orientation, edited-copy callback, one close completion, native path boundary and real environment")
}

Task { @MainActor in
  do { try run(); exit(0) }
  catch { fatalError("Feedback check failed: \(error)") }
}
RunLoop.main.run()
