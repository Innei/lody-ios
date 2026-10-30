import AppKit
import LodyData
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct MacWorkspaceServices {
  var members: @MainActor (_ workspaceId: String) async throws -> WorkspaceMembers
  var rename: @MainActor (_ workspaceId: String, _ name: String) async throws -> Void
  var setIcon: @MainActor (_ workspaceId: String, URL) async throws -> Void
  var pickIcon: @MainActor () async -> URL?

  static var live: MacWorkspaceServices {
    MacWorkspaceServices(
      members: { try await WorkspaceMembers.load(workspaceId: $0) },
      rename: { try await AuthSession.shared.updateWorkspace(id: $0, name: $1) },
      setIcon: { id, url in
        let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? ""
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        _ = try await AuthSession.shared.updateWorkspaceIcon(id: id, file: WorkspaceIconFile(url: url, name: url.lastPathComponent, type: type, size: size))
      },
      pickIcon: {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .webP, .gif]
        panel.allowsMultipleSelection = false
        return await panel.begin() == .OK ? panel.url : nil
      }
    )
  }
}
