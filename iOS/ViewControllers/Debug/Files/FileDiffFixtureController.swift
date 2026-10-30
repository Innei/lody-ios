import LodyCore
import UIKit

@MainActor
final class FileDiffFixtureController: FileDiffController {
  private let fixture: FileFeedbackFixture
  init(params: [String: Any]) {
    fixture = FileFeedbackFixture(params)
    super.init(request: .init(sessionId: params["sessionId"] as! String, entryId: params["entryId"] as? String, path: params["path"] as! String),
      feedback: fixture.feedback, service: FileDiffFixture().service, files: FileContentPreviewController.service)
    fixture.owner = self
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }
}
