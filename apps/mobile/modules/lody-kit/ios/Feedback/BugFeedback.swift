import Darwin
#if canImport(ExpoModulesCore)
import ExpoModulesCore
#endif
import ImageIO
import PhotosUI
import QuickLook
import UIKit
import UniformTypeIdentifiers

@MainActor
final class BugFeedback: NSObject, PHPickerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
  private var pickerPromise: Promise?
  private weak var activePicker: PHPickerViewController?

  static func environment() -> [String: String] {
    var system = utsname()
    uname(&system)
    let capacity = MemoryLayout.size(ofValue: system.machine)
    let hardware = withUnsafePointer(to: &system.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: capacity) {
        String(cString: $0)
      }
    }
    let version = ProcessInfo.processInfo.operatingSystemVersion
    var values = [
      "systemVersion": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
      "deviceModel": ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? hardware,
    ]
    if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String { values["version"] = value }
    if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String { values["build"] = value }
    return values
  }

  private static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("BugFeedback", isDirectory: true)
  }

  private nonisolated static func error(_ key: String) -> Error {
    NSError(domain: "LodyKit.BugFeedback", code: 1, userInfo: [NSLocalizedDescriptionKey: LodyStrings.text(key)])
  }

  static func ownedURL(_ uri: String) throws -> URL {
    guard let url = URL(string: uri), url.isFileURL,
      url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL,
      url.lastPathComponent.range(of: #"^Screenshot-[A-Za-z0-9-]+\.png$"#, options: .regularExpression) != nil,
      url.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL,
      (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) != .typeSymbolicLink else {
      throw error("feedback.imageFailed")
    }
    return url.resolvingSymlinksInPath().standardizedFileURL
  }

  static func details(_ url: URL) throws -> [String: any Sendable] {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let size = attributes[.size] as? Int, size > 0, size <= 20 * 1024 * 1024,
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      CGImageSourceGetType(source) as String? == UTType.png.identifier else { throw error("feedback.imageFailed") }
    return ["uri": url.absoluteString, "name": url.lastPathComponent, "type": "image/png", "size": size]
  }

  nonisolated static func imageData(_ url: URL) throws -> Data {
    // shortcut: screenshots are capped at 4096 px; raise this when larger screenshot exports are needed.
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 4096,
      ] as CFDictionary), let data = UIImage(cgImage: image).pngData(),
      !data.isEmpty, data.count <= 20 * 1024 * 1024 else { throw error("feedback.imageFailed") }
    return data
  }

  static func store(_ data: Data) throws -> URL {
    var folder = directory
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    var excluded = URLResourceValues()
    excluded.isExcludedFromBackup = true
    try folder.setResourceValues(excluded)
    let url = folder.appendingPathComponent("Screenshot-\(UUID().uuidString).png")
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    return url
  }

  func screenshot(command: String, uri: String, from controller: UIViewController?, promise: Promise) {
    do {
      switch command {
      case "pick":
        guard pickerPromise == nil, let controller else { throw Self.error("feedback.unavailable") }
        pickerPromise = promise
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        activePicker = picker
        controller.present(picker, animated: true)
        picker.presentationController?.delegate = self
      case "preview":
        guard let controller else { throw Self.error("feedback.unavailable") }
        let url = try Self.ownedURL(uri)
        _ = try Self.details(url)
        FeedbackScreenshotPreview.present(url: url, from: controller) { error in
          if let error { promise.reject(error); return }
          do { promise.resolve(try Self.details(url)) }
          catch { promise.reject(error) }
        }
      case "remove":
        let url = try Self.ownedURL(uri)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        promise.resolve(nil)
      case "fixture":
        guard LodyUIVerify.enabled else { throw Self.error("feedback.unavailable") }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 520), format: format).pngData { context in
          UIColor.systemBackground.setFill()
          context.fill(CGRect(x: 0, y: 0, width: 390, height: 520))
          ("Offline screenshot" as NSString).draw(at: CGPoint(x: 32, y: 48), withAttributes: [
            .font: UIFont.systemFont(ofSize: 24), .foregroundColor: UIColor.label,
          ])
          UIColor.systemBlue.setFill()
          context.fill(CGRect(x: 32, y: 120, width: 326, height: 80))
        }
        promise.resolve(try Self.details(Self.store(data)))
      default:
        throw Self.error("feedback.unavailable")
      }
    } catch { promise.reject(error) }
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    guard activePicker === picker else { picker.dismiss(animated: true); return }
    guard let provider = results.first?.itemProvider else {
      picker.dismiss(animated: true) { [weak self] in self?.finish(nil) }
      return
    }
    let type = provider.registeredContentTypes.first { $0.conforms(to: .image) } ?? .image
    provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self, weak picker] url, _ in
      let result = Result { () -> Data in
        guard let url else { throw Self.error("feedback.imageFailed") }
        return try Self.imageData(url)
      }
      Task { @MainActor in
        guard let self, let picker, self.activePicker === picker else { return }
        picker.dismiss(animated: true) {
          do {
            let url = try Self.store(result.get())
            self.finish(try Self.details(url))
          } catch { self.finish(nil, error: error) }
        }
      }
    }
  }

  private func finish(_ value: Any?, error: Error? = nil) {
    if let error { pickerPromise?.reject(error) }
    else { pickerPromise?.resolve(value) }
    pickerPromise = nil
    activePicker = nil
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    if presentationController.presentedViewController === activePicker { finish(nil) }
  }

  func share(report: String, uris: [String], from controller: UIViewController?, promise: Promise) {
    let export = FileManager.default.temporaryDirectory.appendingPathComponent("BugFeedback-\(UUID().uuidString)", isDirectory: true)
    do {
      guard let controller, !report.isEmpty, report.count <= 30_000, uris.count <= 4 else { throw Self.error("feedback.shareFailed") }
      let sources = try uris.map { uri -> URL in
        let url = try Self.ownedURL(uri)
        _ = try Self.details(url)
        return url
      }
      try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
      let reportURL = export.appendingPathComponent("Lody-iOS-Bug-Report.md")
      try Data(report.utf8).write(to: reportURL, options: .atomic)
      var items = [reportURL]
      for (index, source) in sources.enumerated() {
        let copy = export.appendingPathComponent("Screenshot-\(index + 1).png")
        try FileManager.default.copyItem(at: source, to: copy)
        items.append(copy)
      }
      let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
      activity.completionWithItemsHandler = { _, completed, _, error in
        try? FileManager.default.removeItem(at: export)
        if let error { promise.reject(error) }
        else { promise.resolve(completed) }
      }
      activity.popoverPresentationController?.sourceView = controller.view
      activity.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
      controller.present(activity, animated: true)
    } catch {
      try? FileManager.default.removeItem(at: export)
      promise.reject(error)
    }
  }
}

@MainActor
private final class FeedbackScreenshotPreview: QLPreviewController, QLPreviewControllerDataSource, @MainActor QLPreviewControllerDelegate {
  private let url: URL
  private var completion: ((Error?) -> Void)?
  private var editError: Error?

  static func present(url: URL, from controller: UIViewController, completion: @escaping (Error?) -> Void) {
    let preview = FeedbackScreenshotPreview(url: url, completion: completion)
    let navigation = UINavigationController(rootViewController: preview)
    navigation.modalPresentationStyle = .pageSheet
    if let sheet = navigation.sheetPresentationController {
      sheet.detents = [.large()]
      sheet.prefersGrabberVisible = true
    }
    controller.present(navigation, animated: true)
  }

  init(url: URL, completion: @escaping (Error?) -> Void) {
    self.url = url
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    dataSource = self
    delegate = self
    let close = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
      self?.dismiss(animated: true)
    })
    close.accessibilityLabel = LodyStrings.text("native.close")
    close.accessibilityIdentifier = "feedback-screenshot-close"
    navigationItem.leftBarButtonItem = close
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
  func previewController(_ controller: QLPreviewController, editingModeFor previewItem: QLPreviewItem) -> QLPreviewItemEditingMode { .updateContents }
  func previewController(_ controller: QLPreviewController, didUpdateContentsOf previewItem: QLPreviewItem) {
    normalize(url)
  }
  func previewController(_ controller: QLPreviewController, didSaveEditedCopyOf previewItem: QLPreviewItem, at modifiedContentsURL: URL) {
    normalize(modifiedContentsURL)
  }
  private func normalize(_ source: URL) {
    do {
      let data = try BugFeedback.imageData(source)
      try data.write(to: url, options: .atomic)
    } catch { editError = error }
  }
  private func finish() {
    let completed = completion
    completion = nil
    completed?(editError)
  }
  func previewControllerDidDismiss(_ controller: QLPreviewController) { finish() }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed || navigationController?.isBeingDismissed == true { finish() }
  }
}
