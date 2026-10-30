import AppKit
import ChatKitCore
import ImageIO
import UniformTypeIdentifiers

@MainActor
protocol MacFileDropTarget: NSView {
  func dropFiles(_ urls: [URL])
}

struct MacDraftAttachment: Equatable {
  let id: String
  let name: String
  let url: URL
  let isImage: Bool
  let bytes: Int
  let thumbnail: CGImage?

  var attachment: CKAttachment {
    CKAttachment(id: id, name: name, bytes: bytes, symbol: isImage ? "photo" : "doc", thumbnail: thumbnail)
  }

  static func thumbnail(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 96,
    ] as CFDictionary)
  }
}

struct MacDraftAttachments {
  enum Rejection: Equatable {
    case tooMany
    case tooLarge(String)
    case unsupported(String)

    var message: String {
      switch self {
      case .tooMany: String(localized: "mac.attachments.limit", bundle: .lodyMac)
      case .tooLarge(let name): String(localized: "mac.attachments.tooLarge \(name)", bundle: .lodyMac)
      case .unsupported(let name): String(localized: "mac.attachments.unsupported \(name)", bundle: .lodyMac)
      }
    }
  }

  static let maxTotal = 16
  static let maxPerKind = 8
  static let pastedImageName = "Pasted Image.png"

  private(set) var items: [MacDraftAttachment] = []
  private let maxBytes: Int

  init(maxBytes: Int = 100 * 1024 * 1024) {
    self.maxBytes = maxBytes
  }

  var isEmpty: Bool { items.isEmpty }

  var payload: [[String: Any]] {
    items.map { ["id": $0.id, "name": $0.name, "uri": $0.url.absoluteString, "kind": $0.isImage ? "image" : "file"] }
  }

  mutating func add(urls: [URL]) -> [Rejection] {
    urls.reduce(into: [Rejection]()) { rejections, url in
      guard let rejection = add(url, name: url.lastPathComponent), !rejections.contains(rejection) else { return }
      rejections.append(rejection)
    }
  }

  mutating func add(pasteboard: NSPasteboard) -> [Rejection]? {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL], !urls.isEmpty {
      return add(urls: urls)
    }
    let text: [NSPasteboard.PasteboardType] = [.string, .rtf, .rtfd, .html]
    guard !(pasteboard.types ?? []).contains(where: text.contains),
          let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    guard (try? png.write(to: url)) != nil else { return [.unsupported(Self.pastedImageName)] }
    defer { try? FileManager.default.removeItem(at: url) }
    return add(url, name: Self.pastedImageName).map { [$0] } ?? []
  }

  private mutating func add(_ url: URL, name: String) -> Rejection? {
    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values?.isRegularFile == true, url.pathExtension.lowercased() != "webarchive", let size = values?.fileSize, size > 0 else {
      return .unsupported(name)
    }
    guard size <= maxBytes else { return .tooLarge(name) }
    let image = Self.isImage(name)
    guard fits(image: image) else { return .tooMany }
    guard let copy = Self.store(url, name: name) else { return .unsupported(name) }
    items.append(MacDraftAttachment(
      id: UUID().uuidString.lowercased(), name: name, url: copy, isImage: image, bytes: size,
      thumbnail: image ? MacDraftAttachment.thumbnail(copy) : nil
    ))
    return nil
  }

  mutating func remove(id: String) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    try? FileManager.default.removeItem(at: items[index].url)
    items.remove(at: index)
  }

  mutating func take() -> [MacDraftAttachment] {
    defer { items = [] }
    return items
  }

  mutating func restore(_ restored: [MacDraftAttachment]) {
    items = restored
  }

  private func fits(image: Bool) -> Bool {
    items.count < Self.maxTotal && items.filter { $0.isImage == image }.count < Self.maxPerKind
  }

  private static func isImage(_ name: String) -> Bool {
    guard let type = UTType(filenameExtension: (name as NSString).pathExtension) else { return false }
    return type.conforms(to: .image) && !type.conforms(to: .movie)
  }

  private static func store(_ url: URL, name: String) -> URL? {
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + name)
    return (try? FileManager.default.copyItem(at: url, to: destination)) == nil ? nil : destination
  }
}
