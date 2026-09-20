import UIKit
import UniformTypeIdentifiers

enum ShareIngest {
  struct Draft { var text = ""; var attachments: [[String: Any]] = [] }
  @MainActor
  static func load(_ providers: [NSItemProvider]) async throws -> Draft {
    guard providers.count <= 32 else { throw CocoaError(.fileReadTooLarge) }
    var draft = Draft()
    var texts: [String] = []
    for provider in providers {
      try Task.checkCancellation()
      if let type = ChatAttachment.transferType(for: provider) {
        let name = provider.suggestedName
        let attachment: ChatAttachment = try await withCheckedThrowingContinuation { continuation in
          if type == .fileURL {
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
              guard let url = item as? URL, let attachment = ChatAttachment.make(suggestedName: name, type: UTType(filenameExtension: url.pathExtension) ?? .data, source: url) else {
                continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)); return
              }
              continuation.resume(returning: attachment)
            }
            return
          }
          provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
            guard let url, let item = ChatAttachment.make(suggestedName: name, type: type, source: url) else {
              continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile)); return
            }
            let size = (try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0 && size <= 100 * 1024 * 1024 else { continuation.resume(throwing: CocoaError(.fileReadTooLarge)); return }
            continuation.resume(returning: item)
          }
        }
        draft.attachments.append(["id": attachment.id, "name": attachment.name, "uri": attachment.url.absoluteString, "kind": attachment.isImage ? "image" : "file"])
      } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) || provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
        let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url : .plainText
        let text: String = try await withCheckedThrowingContinuation { continuation in
          provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
            if let error { continuation.resume(throwing: error) }
            else if let url = item as? URL, !url.isFileURL { continuation.resume(returning: url.absoluteString) }
            else if let text = item as? String { continuation.resume(returning: text) }
            else if let bytes = item as? Data, let text = String(data: bytes, encoding: .utf8) { continuation.resume(returning: text) }
            else { continuation.resume(throwing: CocoaError(.fileReadCorruptFile)) }
          }
        }
        if !text.isEmpty && !texts.contains(text) { texts.append(text) }
      } else { throw CocoaError(.fileReadUnsupportedScheme) }
      guard draft.attachments.filter({ $0["kind"] as? String == "image" }).count <= 8,
        draft.attachments.filter({ $0["kind"] as? String == "file" }).count <= 8 else { throw CocoaError(.fileReadTooLarge) }
    }
    draft.text = texts.joined(separator: "\n\n")
    guard draft.text.utf8.count <= 65536 else { throw CocoaError(.fileReadTooLarge) }
    return draft
  }
}
