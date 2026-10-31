import JavaScriptCore
import UIKit

enum MermaidLayout {
  case diagram(svg: String, size: CGSize)
  case failed(String)
}

@MainActor
final class MermaidEngine {
  static let shared = MermaidEngine(script: Bundle.main.url(forResource: "pele", withExtension: "js"))

  private final class Entry: NSObject {
    let layout: MermaidLayout
    init(_ layout: MermaidLayout) { self.layout = layout }
  }

  private let script: URL?
  private var context: JSContext?
  private let cache: NSCache<NSString, Entry> = {
    let cache = NSCache<NSString, Entry>()
    cache.countLimit = 64
    cache.totalCostLimit = 8 * 1024 * 1024
    return cache
  }()

  init(script: URL?) {
    self.script = script
  }

  func layout(_ source: String) -> MermaidLayout {
    let key = source as NSString
    if let entry = cache.object(forKey: key) { return entry.layout }
    let layout = compute(source)
    var cost = source.utf8.count
    if case let .diagram(svg, _) = layout { cost += svg.utf8.count }
    cache.setObject(Entry(layout), forKey: key, cost: cost)
    return layout
  }

  private func compute(_ source: String) -> MermaidLayout {
    let tooLarge = String(localized: "native.chat.mermaid.tooLarge", bundle: .lody)
    guard source.utf8.count <= 12 * 1024, source.split(whereSeparator: \.isNewline).count <= 128 else { return .failed(tooLarge) }
    guard let context = loadContext() else { return .failed(String(localized: "native.chat.mermaid.failed", bundle: .lody)) }
    context.exception = nil
    let result = context.objectForKeyedSubscript("lodyRenderMermaid")?.call(withArguments: [source])
    if let exception = context.exception {
      context.exception = nil
      return .failed(Self.reason(exception))
    }
    guard let result, let svg = result.forProperty("svg")?.toString(),
      let width = result.forProperty("width")?.toDouble(),
      let height = result.forProperty("height")?.toDouble(),
      width.isFinite, height.isFinite, width > 0, height > 0 else {
      return .failed(String(localized: "native.chat.mermaid.failed", bundle: .lody))
    }
    guard width <= 8192, height <= 8192 else { return .failed(tooLarge) }
    return .diagram(svg: svg, size: CGSize(width: width, height: height))
  }

  private static func reason(_ exception: JSValue) -> String {
    let message = exception.forProperty("message")?.toString() ?? exception.toString() ?? ""
    let line = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed.hasSuffix(":") ? String(trimmed.dropLast()) : trimmed
  }

  private func loadContext() -> JSContext? {
    if let context { return context }
    guard let script, let source = try? String(contentsOf: script, encoding: .utf8), let context = JSContext() else { return nil }
    let measure: @convention(block) (String, Double, Int) -> Double = { text, size, style in
      let base = UIFont(name: style & 4 != 0 ? "CourierNewPSMT" : "ArialMT", size: size) ?? UIFont.systemFont(ofSize: size)
      var traits = base.fontDescriptor.symbolicTraits
      if style & 1 != 0 { traits.insert(.traitBold) }
      if style & 2 != 0 { traits.insert(.traitItalic) }
      let font = base.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: size) } ?? base
      return (text as NSString).size(withAttributes: [.font: font]).width
    }
    context.setObject(measure, forKeyedSubscript: "lodyMeasureText" as NSString)
    context.evaluateScript(source)
    context.evaluateScript("""
      function lodyRenderMermaid(source) {
        return pele.render(source, {
          fontFamily: 'ArialMT', fontFamilyMono: 'CourierNewPSMT', responsive: false,
          links: false, images: false, measurer: { width: lodyMeasureText }
        });
      }
      """)
    guard context.exception == nil else { return nil }
    self.context = context
    return context
  }
}
