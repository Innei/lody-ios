import Foundation
import CryptoKit
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Upload bytes in native code; only the server's attachment references enter Streams.
enum SessionAttachments {
  typealias ProgressHandler = @Sendable (_ attachmentID: String, _ phase: String, _ percent: Int?) -> Void
  static func error(_ message: String) -> NSError {
    NSError(domain: "SessionAttachments", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
  static func segment(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")))!
  }
  static func upload(_ attachments: [[String: Any]], workspace: String, session: String,
    onProgress: @escaping ProgressHandler = { _, _, _ in }) async throws -> [[String: Any]] {
    guard attachments.count <= 16,
          attachments.filter({ $0["kind"] as? String == "image" }).count <= 8,
          attachments.filter({ $0["kind"] as? String == "file" }).count <= 8 else {
      throw error(LodyStrings.text("native.attachment.error.limit"))
    }
    guard let token = try AuthKeychain.read() else { throw error(LodyStrings.text("native.attachment.error.signIn")) }
    var blocks: [[String: Any]] = []
    for attachment in attachments {
      try Task.checkCancellation()
      guard let uri = attachment["uri"] as? String, let url = URL(string: uri), url.isFileURL,
            url.resolvingSymlinksInPath().path.hasPrefix(FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path + "/"),
            let name = attachment["name"] as? String, !name.isEmpty,
            var kind = attachment["kind"] as? String, ["image", "file"].contains(kind) else {
        throw error(LodyStrings.text("native.attachment.error.invalid"))
      }
      let attachmentID = attachment["id"] as? String ?? ""
      onProgress(attachmentID, "preparing", nil)
      let report: @Sendable (Int64, Int64) -> Void = { sent, total in
        guard total > 0 else { return }
        let percent = min(100, max(0, Int(Double(sent) / Double(total) * 100)))
        onProgress(attachmentID, sent >= total ? "verifying" : "uploading", percent)
      }
      if kind == "image", UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true {
        kind = "file"
      }
      let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      guard size.isRegularFile == true, let count = size.fileSize, count > 0, count <= 100 * 1024 * 1024 else {
        throw error(LodyStrings.text("native.attachment.error.empty"))
      }
      let base = "https://api.lody.ai/api/workspaces/\(segment(workspace))/session-\(kind == "image" ? "images" : "files")"
      var result: [String: Any]
      if kind == "image" {
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? ""
        var bytes: Data
        var fileName = name
        var contentType = mime
        if ["image/png", "image/jpeg", "image/webp", "image/gif"].contains(mime), count <= 5 * 1024 * 1024 {
          bytes = try Data(contentsOf: url)
        } else {
          guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2048,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary), let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else {
            throw error(LodyStrings.text("native.attachment.error.imageRead"))
          }
          bytes = jpeg; contentType = "image/jpeg"
          fileName = (name as NSString).deletingPathExtension + ".jpg"
        }
        guard bytes.count <= 5 * 1024 * 1024 else { throw error(LodyStrings.text("native.attachment.error.imageTooLarge")) }
        let boundary = UUID().uuidString
        let safeName = fileName.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"sessionId\"\r\n\r\n\(session)\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8)
        body.append(bytes); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        result = try await request(base + "/upload", token: token, headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"], body: body, onProgress: report)
      } else {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty {
          try Task.checkCancellation(); hash.update(data: data)
        }
        try file.seek(toOffset: 0)
        let prefix = try file.read(upToCount: 8192) ?? Data()
        try file.seek(toOffset: 0)
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let headers = ["x-session-id": session, "x-file-name": segment(name), "x-file-mime-type": mime,
          "x-file-sha256": hash.finalize().map { String(format: "%02x", $0) }.joined(),
          "x-file-size-bytes": String(count), "x-file-text-preview": String(!prefix.contains(0) && String(data: prefix, encoding: .utf8) != nil)]
        let partSize = 16 * 1024 * 1024
        if count <= partSize {
          result = try await request(base + "/upload", token: token, headers: headers, body: try file.readToEnd(), onProgress: report)
        } else {
          let created = try await request(base + "/multipart/create", token: token, headers: headers)
          guard let uploadId = created["uploadId"] as? String, !uploadId.isEmpty,
                let fileId = created["fileId"] as? String, !fileId.isEmpty else { throw error(LodyStrings.text("native.attachment.error.uploadResponse")) }
          let path = base + "/multipart/" + segment(uploadId)
          let identity = ["x-session-id": session, "x-file-id": fileId]
          do {
            var parts: [[String: Any]] = []
            while let data = try file.read(upToCount: partSize), !data.isEmpty {
              let number = parts.count + 1
              let offset = Int64(parts.count * partSize)
              let part = try await request(path + "/part/\(number)", token: token, method: "PUT", headers: identity.merging(["x-file-part-size-bytes": String(data.count)], uniquingKeysWith: { _, new in new }), body: data,
                onProgress: { sent, _ in report(offset + sent, Int64(count)) })
              guard let etag = part["etag"] as? String, !etag.isEmpty else { throw error(LodyStrings.text("native.attachment.error.uploadResponse")) }
              parts.append(["partNumber": number, "etag": etag])
              report(offset + Int64(data.count), Int64(count))
            }
            result = try await request(path + "/complete", token: token, headers: identity.merging(["Content-Type": "application/json"], uniquingKeysWith: { _, new in new }), body: JSONSerialization.data(withJSONObject: ["parts": parts]))
          } catch {
            // Cleanup also runs after cancellation; never retry message dispatch.
            await Task.detached { _ = try? await request(path + "/abort", token: token, method: "DELETE", headers: identity) }.value
            throw error
          }
        }
      }
      guard let block = result[kind] as? [String: Any], block["type"] as? String == kind,
            let id = block[kind == "image" ? "imageId" : "fileId"] as? String, !id.isEmpty,
            block["mimeType"] is String, let bytes = block["sizeBytes"] as? Int, bytes > 0 else {
        throw error(LodyStrings.text("native.attachment.error.uploadResponse"))
      }
      blocks.append(block)
      onProgress(attachmentID, "complete", 100)
    }
    return blocks
  }

  /// Download to disk so a video never becomes a base64/RN or in-memory file body.
  static func download(workspace: String, session: String, fileId: String, fileName: String, sizeBytes: Int?, directory: URL) async throws -> URL {
    guard !workspace.isEmpty, !session.isEmpty, !fileId.isEmpty else {
      throw error(LodyStrings.text("native.attachment.error.invalid"))
    }
    let limit = 100 * 1024 * 1024
    if let sizeBytes, sizeBytes <= 0 || sizeBytes > limit {
      throw error(LodyStrings.text("native.attachment.error.tooLarge"))
    }
    guard let token = try AuthKeychain.read() else { throw error(LodyStrings.text("native.attachment.error.signIn")) }
    let path = [workspace, session, fileId].map(segment)
    var request = URLRequest(url: URL(string: "https://api.lody.ai/api/workspaces/\(path[0])/session-files/\(path[1])/\(path[2])")!, timeoutInterval: 120)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    let (temporary, response) = try await URLSession.shared.download(for: request)
    defer { try? FileManager.default.removeItem(at: temporary) }
    try Task.checkCancellation()
    guard let response = response as? HTTPURLResponse else {
      throw error(LodyStrings.text("native.attachment.error.download"))
    }
    if response.statusCode == 404 || response.statusCode == 410 {
      throw error(LodyStrings.text("native.attachment.error.unavailable"))
    }
    if response.statusCode == 401 || response.statusCode == 403 {
      throw error(LodyStrings.text("native.attachment.error.permissionDenied"))
    }
    guard response.statusCode == 200 else { throw error(LodyStrings.text("native.attachment.error.download")) }
    let count = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard count > 0, count <= limit, sizeBytes == nil || sizeBytes == count else {
      throw error(LodyStrings.text("native.attachment.error.download"))
    }
    let name = (fileName.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
    let safeName = name.isEmpty || name == "." || name == ".." ? "file" : name
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent(safeName)
    try FileManager.default.moveItem(at: temporary, to: destination)
    return destination
  }

  static func request(_ url: String, token: String, method: String = "POST", headers: [String: String], body: Data? = nil,
    onProgress: (@Sendable (Int64, Int64) -> Void)? = nil) async throws -> [String: Any] {
    try Task.checkCancellation()
    var request = URLRequest(url: URL(string: url)!, timeoutInterval: 120)
    request.httpMethod = method; request.httpBody = body
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
    let data: Data
    let response: URLResponse
    if let body, let onProgress {
      request.httpBody = nil
      onProgress(0, Int64(body.count))
      (data, response) = try await URLSession.shared.upload(for: request, from: body,
        delegate: AttachmentUploadDelegate(onProgress: onProgress))
      onProgress(Int64(body.count), Int64(body.count))
    } else {
      (data, response) = try await URLSession.shared.data(for: request)
    }
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
      throw error(LodyStrings.text("native.attachment.error.upload"))
    }
    if data.isEmpty { return [:] }
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw error(LodyStrings.text("native.attachment.error.uploadResponse")) }
    return value
  }
}

final class AttachmentUploadDelegate: NSObject, URLSessionTaskDelegate {
  private let onProgress: @Sendable (Int64, Int64) -> Void
  init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) { self.onProgress = onProgress }
  func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
    onProgress(totalBytesSent, totalBytesExpectedToSend)
  }
}
