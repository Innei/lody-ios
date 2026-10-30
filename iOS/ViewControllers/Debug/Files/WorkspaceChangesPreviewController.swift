import LodyCore
import UIKit

@MainActor
final class WorkspaceChangesPreviewController: WorkspaceChangesController {
  init() {
    super.init(sessionId: "ui-verify-workspace", service: FileDiffFixture().service)
  }
}
