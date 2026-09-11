import QuickLook
import UIKit

@MainActor
final class ContentPreview: NSObject, QLPreviewControllerDataSource, @MainActor QLPreviewControllerDelegate {
  private static var current: ContentPreview?
  private nonisolated static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("preview", isDirectory: true) }
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

#if DEBUG
import UIKit

@MainActor
enum FilePreviewFixture {
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
