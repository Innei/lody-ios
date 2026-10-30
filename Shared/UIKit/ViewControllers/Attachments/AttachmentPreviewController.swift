import QuickLook
import UIKit

final class AttachmentPreviewController: QLPreviewController, QLPreviewControllerDataSource {
  private let urls: [URL]

  init(_ items: [ChatAttachment], index: Int) {
    urls = items.map(\.url)
    super.init(nibName: nil, bundle: nil)
    dataSource = self
    currentPreviewItemIndex = index
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { urls.count }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { urls[index] as NSURL }
}
