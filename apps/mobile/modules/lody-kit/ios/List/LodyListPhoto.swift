import UIKit

@MainActor
enum LodyListPhoto {
  nonisolated static let size = CGSize(width: 36, height: 36)
  private static let cache = NSCache<NSURL, UIImage>()
  private static var waiters: [URL: [(UIImage?) -> Void]] = [:]
  private static var tasks: [URL: URLSessionDataTask] = [:]

  static func url(_ value: String) -> URL? {
    guard let url = URL(string: value), url.user == nil, url.password == nil else { return nil }
    let scheme = url.scheme?.lowercased()
    if scheme == "https" { return url }
    if scheme == "data", value.hasPrefix("data:image/") { return url }
    if url.isFileURL { return url }
    return nil
  }

  static func cached(_ url: URL) -> UIImage? {
    cache.object(forKey: url as NSURL)
  }

  static func image(for url: URL, ready: @escaping (UIImage) -> Void) -> UIImage? {
    if let image = cached(url) { return image }
    if url.isFileURL || url.scheme == "data" {
      load(url) { _ in }
      return cached(url)
    }
    load(url) { image in
      if let image { ready(image) }
    }
    return nil
  }

  static func load(_ url: URL, completion: @escaping (UIImage?) -> Void) {
    if let image = cached(url) {
      completion(image)
      return
    }
    if url.isFileURL || url.scheme == "data" {
      let image = (try? Data(contentsOf: url)).flatMap(decode)
      if let image { cache.setObject(image, forKey: url as NSURL) }
      completion(image)
      return
    }
    waiters[url, default: []].append(completion)
    if tasks[url] != nil { return }
    var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
    request.setValue("image/*", forHTTPHeaderField: "Accept")
    let task = URLSession.shared.dataTask(with: request) { data, response, _ in
      let valid = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
      let image = valid ? data.flatMap(decode) : nil
      DispatchQueue.main.async {
        tasks[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        let callbacks = waiters.removeValue(forKey: url) ?? []
        callbacks.forEach { $0(image) }
      }
    }
    tasks[url] = task
    task.resume()
  }

  static func apply(_ content: inout UIListContentConfiguration, image: UIImage, placeholder: Bool = false) {
    content.image = image
    content.imageProperties.maximumSize = size
    content.imageProperties.reservedLayoutSize = size
    content.imageProperties.cornerRadius = size.width / 2
    content.imageProperties.tintColor = placeholder ? .tertiaryLabel : nil
  }

  nonisolated static func circular(_ image: UIImage) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    format.scale = image.scale
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
      UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
      let scale = max(size.width / max(image.size.width, 1), size.height / max(image.size.height, 1))
      image.draw(in: CGRect(
        x: (size.width - image.size.width * scale) / 2,
        y: (size.height - image.size.height * scale) / 2,
        width: image.size.width * scale,
        height: image.size.height * scale
      ))
    }.withRenderingMode(.alwaysOriginal)
  }

  private nonisolated static func decode(_ data: Data) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(size.width * 3),
    ]
    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return circular(UIImage(cgImage: cg, scale: 1, orientation: .up))
  }
}

enum LodyListGlyph {
  static let symbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title3)
  static let reservedSize = CGSize(
    width: UIListContentConfiguration.ImageProperties.standardDimension,
    height: UIListContentConfiguration.ImageProperties.standardDimension
  )

  static var size: CGSize {
    UIImage(systemName: "square", withConfiguration: symbolConfiguration)?.size
      ?? CGSize(
        width: UIFont.preferredFont(forTextStyle: .title3).pointSize,
        height: UIFont.preferredFont(forTextStyle: .title3).pointSize
      )
  }

  static func apply(_ content: inout UIListContentConfiguration, image: UIImage?, asset: Bool) {
    content.image = image
    content.imageProperties.preferredSymbolConfiguration = symbolConfiguration
    content.imageProperties.reservedLayoutSize = reservedSize
    if asset {
      content.imageProperties.maximumSize = size
    }
  }
}
