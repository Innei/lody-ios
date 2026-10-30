#if DEBUG
import AppKit
import ChatKitCore

struct MacFixtureMedia: CKMediaProvider {
  func image(for ref: CKMediaRef, pixelSize: CGSize) async throws -> CGImage {
    Self.swatch(seed: ref.id, size: pixelSize)
  }

  func fileURL(for ref: CKMediaRef) async throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lody-fixture-\(ref.id).txt")
    try Data((ref.context["name"] ?? ref.id).utf8).write(to: url)
    return url
  }

  static func swatch(seed: String, size: CGSize) -> CGImage {
    let width = max(1, Int(size.width))
    let height = max(1, Int(size.height))
    let hue = CGFloat(abs(seed.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % 360) / 360
    let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let colors = [NSColor(hue: hue, saturation: 0.55, brightness: 0.9, alpha: 1).cgColor, NSColor(hue: hue + 0.12, saturation: 0.65, brightness: 0.6, alpha: 1).cgColor]
    let gradient = CGGradient(colorsSpace: context.colorSpace, colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
    return context.makeImage()!
  }
}
#endif
