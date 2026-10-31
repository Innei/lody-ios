import Litext
import MarkdownParser
import UIKit

@MainActor
protocol MermaidBlock: UIView {
  var source: String { get }
  var state: String { get }
  var imageKey: String { get }
}

@MainActor
enum MarkdownMermaid {
  private static let marker = "\u{F0000}lody-mermaid:"

  static func blocks(_ nodes: [MarkdownBlockNode]) -> [MarkdownBlockNode] {
    // shortcut: MarkdownParser flattens quoted code fences; add upstream block support when quoted diagrams are needed.
    nodes.rewrite { (node: MarkdownBlockNode) -> [MarkdownBlockNode] in
      guard case let .codeBlock(language, source) = node,
        language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mermaid" else { return [node] }
      return [.paragraph(content: [.text(marker + source)])]
    }
  }

  static func attachment(_ text: String, label: TextLabelView, traits: UITraitCollection) -> TextLabel.Attachment? {
    guard text.hasPrefix(marker) else { return nil }
    let source = String(text.dropFirst(marker.count))
    return MermaidAttachment(source: source, layout: MermaidEngine.shared.layout(source), traits: traits, label: label)
  }

  static func copyAction(_ source: String, name: String) -> UIAccessibilityCustomAction {
    UIAccessibilityCustomAction(name: name) { _ in
      UIPasteboard.general.string = source
      return true
    }
  }

  static func copyMenu(_ source: String) -> UIContextMenuConfiguration {
    UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
      UIMenu(children: [UIAction(title: String(localized: "native.chat.copy", bundle: .lody), image: UIImage(systemName: "doc.on.doc")) { _ in
        UIPasteboard.general.string = source
      }])
    }
  }

  static func actions(_ nodes: [MarkdownBlockNode]) -> [UIAccessibilityCustomAction] {
    var actions: [UIAccessibilityCustomAction] = []
    _ = nodes.rewrite { (node: MarkdownInlineNode) -> [MarkdownInlineNode] in
      if case let .text(text) = node, text.hasPrefix(marker) {
        let source = String(text.dropFirst(marker.count))
        actions.append(copyAction(source, name: String(localized: "native.chat.copy", bundle: .lody) + " · Mermaid"))
      }
      return [node]
    }
    return actions
  }

  static func resize(_ label: TextLabelView, width: CGFloat) {
    guard width > 0, label.preferredMaxLayoutWidth != width else { return }
    var hasDiagram = false
    let text = label.attributedText
    text.enumerateAttribute(.litextAttachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
      if value is MermaidAttachment { hasDiagram = true }
    }
    guard hasDiagram else { return }
    label.preferredMaxLayoutWidth = width
    // A new wrapping width alone does not refresh CoreText's run-delegate metrics.
    label.reloadTextLayout()
  }

  static func record(_ root: UIView) {
    guard LodyUIVerify.enabled, let window = root.window else { return }
    var blocks: [[String: Any]] = []
    func walk(_ view: UIView) {
      guard !view.isHidden, view.alpha > 0.01 else { return }
      if let block = view as? MermaidBlock {
        let frame = block.convert(block.bounds, to: window)
        if frame.intersects(window.bounds), frame.width > 0, frame.height > 0 {
          var owner = block.superview
          while let view = owner, view.accessibilityIdentifier == nil { owner = view.superview }
          blocks.append(["owner": owner?.accessibilityIdentifier ?? "", "source": block.source, "state": block.state,
            "image": block.imageKey, "label": block.accessibilityLabel ?? "",
            "x": Double(frame.minX), "y": Double(frame.minY), "width": Double(frame.width), "height": Double(frame.height)])
        }
      }
      for child in view.subviews { walk(child) }
    }
    walk(window)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lody-mermaid.json")
    try? JSONSerialization.data(withJSONObject: blocks, options: .sortedKeys).write(to: url, options: .atomic)
  }
}

@MainActor
private final class MermaidAttachment: TextLabel.Attachment {
  private weak var label: TextLabelView?
  private let source: String
  private let layout: MermaidLayout

  init(source: String, layout: MermaidLayout, traits: UITraitCollection, label: TextLabelView) {
    self.source = source
    self.layout = layout
    self.label = label
    super.init()
    descent = 0
    switch layout {
    case let .diagram(svg, size): view = MermaidDiagramView(source: source, svg: svg, size: size, traits: traits)
    case let .failed(reason): view = MermaidFailureView(source: source, reason: reason)
    }
  }

  override var size: CGSize {
    get {
      var indent: CGFloat = 0
      if let text = label?.attributedText {
        text.enumerateAttribute(.litextAttachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
          guard let attachment = value as? TextLabel.Attachment, attachment === self,
            let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle else { return }
          indent = max(style.headIndent, style.firstLineHeadIndent) + max(0, -style.tailIndent)
        }
      }
      let preferred = label?.preferredMaxLayoutWidth ?? 0
      switch layout {
      case let .diagram(_, natural):
        let available = (preferred > 0 ? preferred : natural.width) - indent
        let width = min(natural.width, max(1, available))
        return CGSize(width: width, height: ceil(width * natural.height / natural.width))
      case let .failed(reason):
        let width = max(1, (preferred > 0 ? preferred : 320) - indent)
        return CGSize(width: width, height: MermaidFailureView.height(width: width, reason: reason, source: source))
      }
    }
    set {}
  }

  override func attributedStringRepresentation() -> NSAttributedString {
    NSAttributedString(string: source)
  }
}
