import Foundation
import CoreText

enum MermaidSVG {
  enum Error: Swift.Error, LocalizedError {
    case invalidDocument
    case unsupportedStyle(String)

    var errorDescription: String? {
      switch self {
      case .invalidDocument: return "Invalid diagram SVG"
      case .unsupportedStyle(let value): return "Unsupported diagram style: \(value)"
      }
    }
  }

  private enum Content {
    case text(String)
    case element(Element)
  }

  private final class Element {
    let name: String
    var attributes: [String: String]
    var textStyle: [String: String] = [:]
    var children: [Content] = []

    init(_ name: String, _ attributes: [String: String]) {
      self.name = name
      self.attributes = attributes
    }
  }

  private final class Reader: NSObject, XMLParserDelegate {
    var root: Element?
    var stack: [Element] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
      let element = Element(name, attributes)
      if let parent = stack.last { parent.children.append(.element(element)) }
      else { root = element }
      stack.append(element)
    }

    func parser(_ parser: XMLParser, foundCharacters text: String) {
      guard let current = stack.last else { return }
      if case .text(let previous) = current.children.last {
        current.children.removeLast()
        current.children.append(.text(previous + text))
      } else { current.children.append(.text(text)) }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
      stack.removeLast()
    }
  }

  static func normalize(_ svg: String, bg: String, fg: String) throws -> String {
    let reader = Reader()
    let parser = XMLParser(data: Data(svg.utf8))
    parser.shouldResolveExternalEntities = false
    parser.externalEntityResolvingPolicy = .never
    parser.delegate = reader
    guard parser.parse(), let root = reader.root, root.name == "svg" else {
      throw Error.invalidDocument
    }
    let overrides = [
      "--pele-bg": bg, "--pele-fg": fg, "--pele-line": fg,
      "--pele-muted": "#737373", "--pele-border": "#737373",
      "--pele-surface": mix(bg, fg, fraction: 0.06),
      "--pele-surface-alt": mix(bg, fg, fraction: 0.12),
    ]
    try normalize(root, variables: [:], overrides: overrides)
    return write(root)
  }

  private static func normalize(_ element: Element, variables: [String: String], overrides: [String: String], textStyle: [String: String] = [:]) throws {
    var variables = variables
    let declarations = (element.attributes.removeValue(forKey: "style") ?? "")
      .split(separator: ";").compactMap { part -> (String, String)? in
        guard let colon = part.firstIndex(of: ":") else { return nil }
        return (part[..<colon].trimmingCharacters(in: .whitespaces),
                part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces))
      }
    for (key, value) in declarations where key.hasPrefix("--") { variables[key] = value }
    variables.merge(overrides) { _, override in override }
    for (key, value) in declarations where !key.hasPrefix("--") {
      switch key {
      case "height", "max-width", "letter-spacing", "word-spacing", "text-transform", "direction": break
      case "font":
        if let size = value.components(separatedBy: "px").first, Double(size) != nil {
          element.attributes["font-size"] = size
        }
      default: element.attributes[key] = value
      }
    }
    for (key, value) in element.attributes {
      element.attributes[key] = try resolve(value, variables: variables)
    }
    element.textStyle = textStyle.merging(element.attributes.filter { $0.key.hasPrefix("font-") }) { _, child in child }
    for child in element.children {
      if case .element(let node) = child { try normalize(node, variables: variables, overrides: overrides, textStyle: element.textStyle) }
    }
    // CoreSVG ignores tspan coordinates. Put each positioned line on its own text element.
    if element.name != "text" {
      element.children = try element.children.flatMap { child -> [Content] in
        guard case .element(let node) = child, node.name == "text" else { return [child] }
        return try textLines(node).map(Content.element)
      }
    }
  }

  private static func textLines(_ text: Element) throws -> [Element] {
    var output: [Element] = []
    var position = text.attributes
    var runs: [(String, [String: String])] = []
    func flush() throws {
      guard !runs.isEmpty else { return }
      let measured = try runs.map { value, attributes -> (String, [String: String], Double) in
        let rawSize = attributes["font-size"] ?? "16"
        guard let size = Double(rawSize.replacingOccurrences(of: "px", with: "")),
              size.isFinite, size > 0, size <= 200
        else { throw Error.unsupportedStyle("font-size: \(rawSize)") }
        let family = (attributes["font-family"] ?? "ArialMT").components(separatedBy: ",")[0]
          .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        let postscript = ["Arial": "ArialMT", "Courier New": "CourierNewPSMT"][family] ?? family
        let base = CTFontCreateWithName(postscript as CFString, size, nil)
        var traits: CTFontSymbolicTraits = []
        if ["bold", "bolder"].contains(attributes["font-weight"] ?? "") || (Int(attributes["font-weight"] ?? "") ?? 0) >= 600 { traits.insert(.traitBold) }
        if ["italic", "oblique"].contains(attributes["font-style"] ?? "") { traits.insert(.traitItalic) }
        let font = CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, [.traitBold, .traitItalic]) ?? base
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
          NSAttributedString.Key(kCTFontAttributeName as String): font,
        ]))
        var attributes = attributes
        attributes["font-family"] = CTFontCopyPostScriptName(font) as String
        return (value, attributes, CTLineGetTypographicBounds(line, nil, nil, nil))
      }
      var x = Double(position["x"] ?? "0") ?? 0
      let width = measured.reduce(0) { $0 + $1.2 }
      if position["text-anchor"] == "middle" { x -= width / 2 }
      else if position["text-anchor"] == "end" { x -= width }
      for (value, attributes, advance) in measured {
        let node = outlinedText(value, attributes: position.merging(attributes) { _, run in run }, x: x)
        output.append(node)
        x += advance
      }
      runs.removeAll(keepingCapacity: true)
    }
    func consume(_ children: [Content], attributes: [String: String]) throws {
      for child in children {
        switch child {
        case .text(let value):
          runs.append((value, attributes.filter { !["x", "y", "dx", "dy", "transform", "text-anchor"].contains($0.key) }))
        case .element(let span):
          let merged = attributes.merging(span.attributes) { _, child in child }
          if span.attributes["x"] != nil || span.attributes["y"] != nil {
            try flush()
            position = text.attributes.merging(merged.filter { ["x", "y", "dx", "dy", "transform", "text-anchor"].contains($0.key) }) { _, child in child }
          }
          try consume(span.children, attributes: merged)
        }
      }
    }
    try consume(text.children, attributes: text.textStyle.merging(text.attributes) { _, child in child })
    try flush()
    return output
  }

  // CoreSVG also drops span font styles and spaces. Glyph outlines preserve CoreText's layout.
  private static func outlinedText(_ value: String, attributes: [String: String], x: Double) -> Element {
    let font = CTFontCreateWithName((attributes["font-family"] ?? "ArialMT") as CFString,
                                  Double(attributes["font-size"]?.replacingOccurrences(of: "px", with: "") ?? "16") ?? 16, nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
      NSAttributedString.Key(kCTFontAttributeName as String): font,
    ]))
    let node = Element("g", attributes.filter { !["x", "y", "text-anchor"].contains($0.key) })
    node.attributes["aria-label"] = value
    let y = Double(attributes["y"] ?? "0") ?? 0
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
      let count = CTRunGetGlyphCount(run)
      let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
      var glyphs = [CGGlyph](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      var indices = [CFIndex](repeating: 0, count: count)
      CTRunGetGlyphs(run, CFRange(), &glyphs)
      CTRunGetPositions(run, CFRange(), &positions)
      CTRunGetStringIndices(run, CFRange(), &indices)
      for i in 0..<count {
        if let path = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) {
          var transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1,
                                           tx: x + positions[i].x, ty: y - positions[i].y)
          let outline = path.copy(using: &transform)!
          let glyph = Element("path", ["d": pathData(outline)])
          node.children.append(.element(glyph))
        } else {
          // Color emoji have no outline; retain the native text fallback for that cluster.
          let start = indices[i]
          let range = CTRunGetStringRange(run)
          let end = indices.filter { $0 > start }.min() ?? (range.location + range.length)
          guard start >= 0, end > start, end <= value.utf16.count else { continue }
          let cluster = (value as NSString).substring(with: NSRange(location: start, length: end - start))
          if cluster.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
          let glyph = Element("text", [
            "x": String(x + positions[i].x), "y": String(y - positions[i].y),
            "font-family": CTFontCopyPostScriptName(runFont) as String,
            "font-size": String(Double(CTFontGetSize(runFont))),
          ])
          glyph.children = [.text(cluster)]
          node.children.append(.element(glyph))
        }
      }
    }
    return node
  }

  private static func pathData(_ path: CGPath) -> String {
    func point(_ p: CGPoint) -> String { "\(p.x),\(p.y)" }
    var result = ""
    path.applyWithBlock { element in
      let e = element.pointee
      switch e.type {
      case .moveToPoint: result += "M" + point(e.points[0])
      case .addLineToPoint: result += "L" + point(e.points[0])
      case .addQuadCurveToPoint: result += "Q" + point(e.points[0]) + " " + point(e.points[1])
      case .addCurveToPoint: result += "C" + point(e.points[0]) + " " + point(e.points[1]) + " " + point(e.points[2])
      case .closeSubpath: result += "Z"
      @unknown default: break
      }
    }
    return result
  }

  private static func resolve(_ value: String, variables: [String: String]) throws -> String {
    var result = value
    let variable = try NSRegularExpression(pattern: #"var\((--[\w-]+)(?:,([^()]*))?\)"#)
    for _ in 0..<32 {
      let matches = variable.matches(in: result, range: NSRange(result.startIndex..., in: result))
      if matches.isEmpty { break }
      for match in matches.reversed() {
        let name = String(result[Range(match.range(at: 1), in: result)!])
        let fallback = Range(match.range(at: 2), in: result).map { String(result[$0]) } ?? ""
        result.replaceSubrange(Range(match.range, in: result)!, with: variables[name] ?? fallback)
      }
    }
    let colorMix = try NSRegularExpression(pattern: #"color-mix\(in srgb,\s*(#[a-fA-F0-9]{3,8})\s+([\d.]+)%,\s*(#[a-fA-F0-9]{3,8})\s*\)"#)
    for match in colorMix.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
      let first = String(result[Range(match.range(at: 1), in: result)!])
      guard let percentage = Double(result[Range(match.range(at: 2), in: result)!]),
            percentage.isFinite, (0...100).contains(percentage)
      else { throw Error.unsupportedStyle(value) }
      let second = String(result[Range(match.range(at: 3), in: result)!])
      result.replaceSubrange(Range(match.range, in: result)!, with: mix(second, first, fraction: percentage / 100))
    }
    guard !result.contains("var("), !result.contains("color-mix(") else { throw Error.unsupportedStyle(value) }
    return result
  }

  private static func mix(_ first: String, _ second: String, fraction: Double) -> String {
    func rgb(_ value: String) -> [Double] {
      var hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
      if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
      guard hex.count >= 6, let n = UInt64(hex.prefix(6), radix: 16) else { return [0, 0, 0] }
      return [Double((n >> 16) & 255), Double((n >> 8) & 255), Double(n & 255)]
    }
    let a = rgb(first), b = rgb(second)
    return "#" + zip(a, b).map { String(format: "%02x", Int(($0 * (1 - fraction) + $1 * fraction).rounded())) }.joined()
  }

  private static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }

  private static func write(_ element: Element) -> String {
    let attributes = element.attributes.sorted { $0.key < $1.key }
      .map { " \($0.key)=\"\(escape($0.value))\"" }.joined()
    let content = element.children.map { child in
      switch child {
      case .text(let value): return escape(value)
      case .element(let node): return write(node)
      }
    }.joined()
    return "<\(element.name)\(attributes)>\(content)</\(element.name)>"
  }
}
