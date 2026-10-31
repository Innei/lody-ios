import Darwin
import UIKit

enum MermaidRaster {
  enum Failure: Error {
    case unavailable
    case undecodable
  }

  private typealias Create = @convention(c) (CFData, CFDictionary?) -> OpaquePointer?
  private typealias Draw = @convention(c) (CGContext, OpaquePointer) -> Void
  private typealias Canvas = @convention(c) (OpaquePointer) -> CGSize
  private typealias Release = @convention(c) (OpaquePointer) -> Void

  private struct CoreSVG: @unchecked Sendable {
    let create: Create
    let draw: Draw
    let canvas: Canvas
    let release: Release
  }

  private static let coreSVG: CoreSVG? = {
    let handle = UnsafeMutableRawPointer(bitPattern: -2)
    guard let create = dlsym(handle, "CGSVGDocumentCreateFromData"),
      let draw = dlsym(handle, "CGContextDrawSVGDocument"),
      let canvas = dlsym(handle, "CGSVGDocumentGetCanvasSize"),
      let release = dlsym(handle, "CGSVGDocumentRelease") else { return nil }
    return CoreSVG(create: unsafeBitCast(create, to: Create.self), draw: unsafeBitCast(draw, to: Draw.self),
      canvas: unsafeBitCast(canvas, to: Canvas.self), release: unsafeBitCast(release, to: Release.self))
  }()

  static func image(svg: String, size: CGSize, background: String, foreground: String, scale: CGFloat) throws -> UIImage {
    guard let coreSVG else { throw Failure.unavailable }
    let normalized = try MermaidSVG.normalize(svg, bg: background, fg: foreground)
    guard let document = coreSVG.create(Data(normalized.utf8) as CFData, nil) else { throw Failure.undecodable }
    defer { coreSVG.release(document) }
    let canvas = coreSVG.canvas(document)
    guard canvas.width > 0, canvas.height > 0 else { throw Failure.undecodable }
    let format = UIGraphicsImageRendererFormat()
    format.scale = min(scale, sqrt(32_000_000 / (size.width * size.height)))
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
      (UIColor(mermaidHex: background) ?? .white).setFill()
      renderer.fill(CGRect(origin: .zero, size: size))
      let context = renderer.cgContext
      // CoreSVG draws in Core Graphics' bottom-left space; UIKit's renderer context is flipped.
      context.translateBy(x: 0, y: size.height)
      context.scaleBy(x: size.width / canvas.width, y: -size.height / canvas.height)
      coreSVG.draw(context, document)
    }
  }

  static func hex(_ color: UIColor) -> String {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    let channels = [red, green, blue].map { Int((min(max($0, 0), 1) * 255).rounded()) }
    return String(format: "#%02x%02x%02x", channels[0], channels[1], channels[2])
  }
}

private extension UIColor {
  convenience init?(mermaidHex value: String) {
    let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard hex.count == 6, let number = UInt64(hex, radix: 16) else { return nil }
    self.init(red: CGFloat((number >> 16) & 255) / 255, green: CGFloat((number >> 8) & 255) / 255,
      blue: CGFloat(number & 255) / 255, alpha: 1)
  }
}
