import QuickLook
import UIKit

@MainActor
final class ContentPreview: NSObject, QLPreviewControllerDataSource, @MainActor QLPreviewControllerDelegate {
  private static var current: ContentPreview?
  nonisolated static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("preview", isDirectory: true) }
  private let url: URL

  private init(url: URL) { self.url = url }

  nonisolated static func clearAll() {
    try? FileManager.default.removeItem(at: root)
  }

  static func present(handle: String, from controller: UIViewController) throws {
    guard let content = ContentStore.shared.get(handle) else {
      throw NSError(domain: "LodyKit.ContentPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: "content_expired"])
    }
    let directory = root.appendingPathComponent(handle, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = (content.path as NSString).lastPathComponent
    let url = directory.appendingPathComponent(name.isEmpty ? "file" : name)
    try content.data.write(to: url, options: .atomic)
    let preview = ContentPreview(url: url)
    let viewer = QLPreviewController()
    viewer.dataSource = preview
    viewer.delegate = preview
    current = preview
    controller.present(viewer, animated: true)
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    url as NSURL
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    if Self.current === self { Self.current = nil }
  }
}

/// Quick Look provides video playback, document previews and the system share action.
@MainActor
final class SessionFilePreview: QLPreviewController, QLPreviewControllerDataSource, @MainActor QLPreviewControllerDelegate {
  private let file: ChatMessageAttachment
  private let workspace: String
  private let session: String
  private let directory = ContentPreview.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
  private var url: URL?
  private var download: Task<Void, Never>?
  #if DEBUG
  private var fixtureAttempt = 0
  #endif

  init(file: ChatMessageAttachment, workspace: String, session: String) {
    self.file = file
    self.workspace = workspace
    self.session = file.storageSessionId ?? session
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    dataSource = self
    delegate = self
    load()
  }

  private func load() {
    download?.cancel()
    var loading = UIContentUnavailableConfiguration.loading()
    loading.text = LodyStrings.text("native.attachment.preview.loading")
    loading.background.backgroundColor = .systemBackground
    loading.button.title = LodyStrings.text("native.close")
    loading.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.dismiss(animated: true) }
    contentUnavailableConfiguration = loading
    #if DEBUG
    fixtureAttempt += 1
    let attempt = fixtureAttempt
    #endif
    download = Task { [weak self, file, workspace, session, directory] in
      do {
        guard file.transport == nil || file.transport == "r2" else {
          throw SessionAttachments.error(LodyStrings.text("native.attachment.error.pending"))
        }
        let url: URL
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-verify"), session == "ui-verify-attachments" {
          try await Task.sleep(for: .milliseconds(file.id == "cancel" ? 4000 : 1200))
          url = try FilePreviewFixture.attachment(file.id, attempt: attempt, directory: directory)
        } else {
          url = try await SessionAttachments.download(workspace: workspace, session: session, fileId: file.id,
            fileName: file.fileName, sizeBytes: file.sizeBytes, directory: directory)
        }
        #else
        url = try await SessionAttachments.download(workspace: workspace, session: session, fileId: file.id,
          fileName: file.fileName, sizeBytes: file.sizeBytes, directory: directory)
        #endif
        try Task.checkCancellation()
        guard let self else { try? FileManager.default.removeItem(at: directory); return }
        self.url = url
        self.contentUnavailableConfiguration = nil
        self.reloadData()
      } catch {
        try? FileManager.default.removeItem(at: directory)
        guard !Task.isCancelled, let self else { return }
        var failed = UIContentUnavailableConfiguration.empty()
        failed.background.backgroundColor = .systemBackground
        failed.image = UIImage(systemName: "doc.badge.ellipsis")
        failed.text = file.fileName
        failed.secondaryText = error.localizedDescription
        failed.secondaryButton.title = LodyStrings.text("native.close")
        failed.secondaryButtonProperties.primaryAction = UIAction { [weak self] _ in self?.dismiss(animated: true) }
        if file.transport != "local" {
          failed.button.title = LodyStrings.text("native.attachment.preview.retry")
          failed.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.load() }
        }
        self.contentUnavailableConfiguration = failed
      }
    }
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    download?.cancel()
    try? FileManager.default.removeItem(at: directory)
  }

  deinit {
    download?.cancel()
    try? FileManager.default.removeItem(at: directory)
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { url == nil ? 0 : 1 }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    url! as NSURL
  }
}

#if DEBUG
import UIKit

@MainActor
enum FilePreviewFixture {
  static func attachment(_ id: String, attempt: Int, directory: URL) throws -> URL {
    if id == "missing" { throw SessionAttachments.error(LodyStrings.text("native.attachment.error.unavailable")) }
    if id == "retry", attempt == 1 { throw SessionAttachments.error(LodyStrings.text("native.attachment.error.download")) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if id == "video" {
      let source = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("ui-verify-attachment.mp4")
      let url = directory.appendingPathComponent("video.mp4")
      try FileManager.default.copyItem(at: source, to: url)
      return url
    }
    if id == "pdf" {
      let url = directory.appendingPathComponent("report.pdf")
      let body = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 500)).pdfData { context in
        context.beginPage()
        ("MCP attachment preview" as NSString).draw(at: CGPoint(x: 32, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
      }
      try body.write(to: url)
      return url
    }
    let url = directory.appendingPathComponent("report.txt")
    try Data("MCP attachment preview\n\nDownloaded files open with native Quick Look.\n".utf8).write(to: url)
    return url
  }

  static func response(_ payload: String, listing: Bool = false) -> String? {
    guard ProcessInfo.processInfo.arguments.contains("--ui-verify"),
      let data = payload.data(using: .utf8),
      let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      args["sessionId"] as? String == "ui-verify-files",
      let path = (args["path"] ?? args["relativePath"]) as? String else { return nil }
    if listing { return #"{"entries":[{"name":"report.md","type":"file"},{"name":"sample.swift","type":"file"}],"truncated":false}"# }
    let name = (path as NSString).lastPathComponent
    var kind = "text"
    let body: Data
    switch name {
    case "report.md":
      body = Data("# Performance report\n\nA **rendered document**, with a table and a related file.\n\n| Run | FPS |\n| --- | --- |\n| Light | 60 |\n| Dark | 60 |\n\n[Source](sample.swift#L2)\n".utf8)
    case "SKILL.md" where path == "skills/review/SKILL.md":
      body = Data("# Review skill\n\nRead the diff and report actionable findings.\n".utf8)
    case "sample.swift" where path == "docs/sample.swift": body = Data("// File preview\nlet answer = 42\nprint(answer)\n".utf8)
    case "photo.png":
      kind = "image"
      body = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 200)).pngData { context in
        UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
        ("Lody preview" as NSString).draw(at: CGPoint(x: 60, y: 85), withAttributes: [.font: UIFont.systemFont(ofSize: 28), .foregroundColor: UIColor.white])
      }
    case "document.pdf":
      kind = "binary"
      body = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 500)).pdfData { context in
        context.beginPage()
        ("PDF preview" as NSString).draw(at: CGPoint(x: 40, y: 60), withAttributes: [.font: UIFont.systemFont(ofSize: 28)])
      }
    default:
      return #"{"status":"error","path":"missing.txt","code":"file_not_found"}"#
    }
    let handle = ContentStore.shared.put(StoredContent(data: body, kind: kind, path: path, session: "ui-verify-files", mimeType: nil))
    let result: [String: Any] = ["status": "ok", "path": path, "kind": kind, "handle": handle, "bytes": body.count]
    return String(data: try! JSONSerialization.data(withJSONObject: result), encoding: .utf8)
  }
}
#endif
