import Foundation
import CryptoKit
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Upload bytes in native code; only the server's attachment references enter Streams.
enum SessionAttachments {
  static func error(_ message: String) -> NSError {
    NSError(domain: "SessionAttachments", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
  static func segment(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")))!
  }
  static func upload(_ attachments: [[String: Any]], workspace: String, session: String) async throws -> [[String: Any]] {
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
            let kind = attachment["kind"] as? String, ["image", "file"].contains(kind) else {
        throw error(LodyStrings.text("native.attachment.error.invalid"))
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
        result = try await request(base + "/upload", token: token, headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"], body: body)
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
          result = try await request(base + "/upload", token: token, headers: headers, body: try file.readToEnd())
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
              let part = try await request(path + "/part/\(number)", token: token, method: "PUT", headers: identity.merging(["x-file-part-size-bytes": String(data.count)], uniquingKeysWith: { _, new in new }), body: data)
              guard let etag = part["etag"] as? String, !etag.isEmpty else { throw error(LodyStrings.text("native.attachment.error.uploadResponse")) }
              parts.append(["partNumber": number, "etag": etag])
            }
            result = try await request(path + "/complete", token: token, headers: identity.merging(["Content-Type": "application/json"], uniquingKeysWith: { _, new in new }), body: JSONSerialization.data(withJSONObject: ["parts": parts]))
          } catch {
            // Cleanup also runs after cancellation; never retry message dispatch.
            _ = await Task.detached { try? await request(path + "/abort", token: token, method: "DELETE", headers: identity) }.value
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
    }
    return blocks
  }

  static func request(_ url: String, token: String, method: String = "POST", headers: [String: String], body: Data? = nil) async throws -> [String: Any] {
    try Task.checkCancellation()
    var request = URLRequest(url: URL(string: url)!, timeoutInterval: 120)
    request.httpMethod = method; request.httpBody = body
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
      throw error(LodyStrings.text("native.attachment.error.upload"))
    }
    if data.isEmpty { return [:] }
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw error(LodyStrings.text("native.attachment.error.uploadResponse")) }
    return value
  }
}
