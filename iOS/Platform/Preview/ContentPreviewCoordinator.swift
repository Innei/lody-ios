import QuickLook
import UIKit

@MainActor
final class ContentPreviewCoordinator: NSObject, QLPreviewControllerDataSource, @MainActor QLPreviewControllerDelegate {
  private static var current: ContentPreviewCoordinator?
  nonisolated static var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("preview", isDirectory: true) }
  private let url: URL

  private init(url: URL) { self.url = url }

  nonisolated static func clearAll() {
    try? FileManager.default.removeItem(at: root)
  }

  static func prepare(handle: String, directory: URL) throws -> URL {
    guard let content = ContentStore.shared.get(handle) else {
      throw NSError(domain: "LodyKit.ContentPreviewCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "content_expired"])
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let name = (content.path as NSString).lastPathComponent
    let url = directory.appendingPathComponent(name.isEmpty ? "file" : name)
    try content.data.write(to: url, options: .atomic)
    return url
  }

  static func present(handle: String, from controller: UIViewController) throws {
    let directory = root.appendingPathComponent(handle, isDirectory: true)
    let url = try prepare(handle: handle, directory: directory)
    let preview = ContentPreviewCoordinator(url: url)
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
