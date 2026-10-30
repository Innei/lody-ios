import LodyCore
import UIKit

@MainActor
final class FilesFixtureController: FilesController {
  init(params: RuntimeContract.ListDirParams) {
    super.init(params: params, service: .init(list: { request in
      let payload = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
      let json = FilePreviewFixture.response(payload, listing: true)!
      return try JSONDecoder().decode(RuntimeContract.DirectoryListing.self, from: Data(json.utf8))
    }, open: { sessionId, path, controller in
      await FileContentController.open(sessionId: sessionId, path: path,
        service: .init(read: { session, path in
          // Keep the loading scene observable across the native sheet transition.
          if path.hasSuffix("report.md") { try await Task.sleep(for: .seconds(3)) }
          return try await FileContentPreviewController.service.read(session, path)
        }, quickLook: FileContentService.live.quickLook), from: controller)
    }))
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }
}
