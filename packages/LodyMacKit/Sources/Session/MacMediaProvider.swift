import AppKit
import ChatKitCore
import ImageIO
import LodyData

struct MacMediaProvider: CKMediaProvider {
  let workspace: String
  let session: String

  func image(for ref: CKMediaRef, pixelSize: CGSize) async throws -> CGImage {
    if let local = ref.context["local"].flatMap(URL.init(string:)), local.isFileURL {
      return try Self.decode(try Data(contentsOf: local), maxPixel: max(pixelSize.width, pixelSize.height))
    }
    guard let token = try AuthKeychain.read() else { throw SessionAttachments.error("signed out") }
    let width = min(2048, Int((pixelSize.width / 256).rounded(.up)) * 256)
    var request = URLRequest(url: SessionAttachments.imageThumbnailURL(workspace: workspace, session: storage(ref), imageId: ref.id, width: width))
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("image/*,*/*", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else {
      throw SessionAttachments.error("thumbnail \(ref.id)")
    }
    return try Self.decode(data, maxPixel: max(pixelSize.width, pixelSize.height))
  }

  func fileURL(for ref: CKMediaRef) async throws -> URL {
    if let local = ref.context["local"].flatMap(URL.init(string:)), local.isFileURL { return local }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lody-attachments/\(ref.id)", isDirectory: true)
    let name = ref.context["name"] ?? ref.id
    let cached = directory.appendingPathComponent((name as NSString).lastPathComponent)
    if FileManager.default.fileExists(atPath: cached.path) { return cached }
    return try await SessionAttachments.download(
      workspace: workspace, session: storage(ref), fileId: ref.id, fileName: name,
      sizeBytes: ref.context["size"].flatMap(Int.init), directory: directory, image: ref.context["kind"] == "image"
    )
  }

  private func storage(_ ref: CKMediaRef) -> String {
    ref.context["session"].flatMap { $0.isEmpty ? nil : $0 } ?? session
  }

  static func decode(_ data: Data, maxPixel: CGFloat) throws -> CGImage {
    let options = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixel)),
    ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
      throw SessionAttachments.error("undecodable image")
    }
    return image
  }
}
