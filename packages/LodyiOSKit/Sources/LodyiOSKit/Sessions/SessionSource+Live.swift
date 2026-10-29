import Foundation

extension SessionSource {
  static let live = SessionSource(
    changes: [.lodyAuthDidChange, .lodyCatalogDidChange, .lodySessionCatalogPreviewDidChange, .lodySessionViewsDidChange],
    read: { SessionCatalogPreview.state ?? SessionPublished.state() },
    raw: { id in SessionCatalogPreview.state == nil ? SessionPublished.raw(id) : SessionCatalogPreview.raw(id) },
    write: { workspaceId, sessionId, write in
      if NativeHomeFixture.active, case .delete(let ids) = write {
        try await NativeHomeFixture.request("deleteSessions", ["sessionId": sessionId, "sessionIds": ids])
        return
      }
      try await SessionSource.cloud(workspaceId, sessionId, write)
    }
  )
}
