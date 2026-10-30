import LodyCore
import UIKit

@MainActor
final class FileContentFixtureController: FileContentController {
  private let fixture: FileFeedbackFixture
  init(params: [String: Any]) {
    fixture = FileFeedbackFixture(params)
    super.init(sessionId: params["sessionId"] as! String, path: params["path"] as! String,
      line: params["line"] as? Int, preview: params["preview"] as? Bool ?? false,
      feedback: fixture.feedback, service: FileContentPreviewController.service)
    fixture.owner = self
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }
}
