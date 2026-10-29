import Foundation
import LodyData

@MainActor
struct MacSessionsSource {
  var changes: [Notification.Name]
  var read: @MainActor () -> SessionListState
  var write: SessionWriteService

  static let live = MacSessionsSource(
    changes: [.lodyAuthDidChange, .lodyCatalogDidChange, .lodySessionViewsDidChange],
    read: { SessionPublished.state() },
    write: { workspaceId, sessionId, write in try await SessionSource.cloud(workspaceId, sessionId, write) }
  )

  static func fixture(_ state: SessionListState) -> MacSessionsSource {
    MacSessionsSource(changes: [], read: { state }, write: { _, _, _ in })
  }
}
