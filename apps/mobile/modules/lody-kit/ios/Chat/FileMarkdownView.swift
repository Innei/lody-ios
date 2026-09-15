import Litext
import MarkdownParser
import MarkdownView
import UIKit

// Decorate parsed links, never regex-rewrite Markdown source (code fences and
// escaped text must remain literal). Sizing and visible views use this together.
final class FileMarkdownView: MarkdownTextView {
  private static let marker = "\u{F0000}lody-file:"

  static func content(_ source: MarkdownContent) -> MarkdownContent {
    let blocks = source.blocks.rewrite { (node: MarkdownInlineNode) -> [MarkdownInlineNode] in
      guard case let .link(destination, children) = node,
        ChatFileLink(destination) != nil else { return [node] }
      return [.link(destination: destination, children: [.text(marker + destination)] + children)]
    }
    return MarkdownContent(blocks: blocks, rendered: source.rendered, highlightMaps: source.highlightMaps, locale: source.locale)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    ChatTableBleed.apply(to: self)
    ChatWordSelection.attach(under: self)
    #if DEBUG
    ChatContextViewProbe.record(self)
    #endif
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    if super.point(inside: point, with: event) { return true }
    return ChatTableBleed.tables(in: self).contains {
      ChatTableBleed.contains($0, point: point, from: self, event: event)
    }
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    for table in ChatTableBleed.tables(in: self) {
      if let hit = ChatTableBleed.hit(table, point: point, from: self, event: event) { return hit }
    }
    return super.hitTest(point, with: event)
  }

  override func decorate(inlineText text: NSAttributedString, theme: MarkdownTheme) -> NSAttributedString {
    guard text.string.hasPrefix(Self.marker) else { return text }
    let href = String(text.string.dropFirst(Self.marker.count))
    guard let target = ChatFileLink(href) else { return text }
    let icon = FileLinkButton(type: .system)
    icon.setImage(MaterialFileIcon.image(for: target.path), for: .normal)
    icon.imageView?.contentMode = .scaleAspectFit
    icon.tintColor = .lodyAccent
    icon.accessibilityLabel = (target.path as NSString).lastPathComponent
    icon.addAction(UIAction { [weak self] _ in
      self?.linkHandler?(.string(href), NSRange(location: 0, length: 0), .zero)
    }, for: .touchUpInside)
    let attachment = TextLabel.Attachment()
    attachment.size = CGSize(width: theme.fonts.body.pointSize + 5, height: theme.fonts.body.pointSize)
    attachment.view = icon
    let result = NSMutableAttributedString(attributedString: attachment.attributedString(attributes: text.attributes(at: 0, effectiveRange: nil)))
    // The run delegate supplies the icon's width; no placeholder glyph is drawn.
    result.replaceCharacters(in: NSRange(location: 0, length: result.length), with: "\u{200B}")
    return result
  }

  func fileActions(_ content: MarkdownContent) -> [UIAccessibilityCustomAction] {
    func inlineNodes(_ blocks: [MarkdownBlockNode]) -> [MarkdownInlineNode] {
      blocks.flatMap { block in
        switch block {
        case .paragraph(let content), .heading(_, let content): return content
        case .table(_, let rows): return rows.flatMap { $0.cells.flatMap(\.content) }
        default: return inlineNodes(block.children)
        }
      }
    }
    // Read the parsed content, including tables and the latest streamed links,
    // rather than the label's previous frame while throttled rendering catches up.
    return inlineNodes(content.blocks).collect { node -> [UIAccessibilityCustomAction] in
      guard case let .link(href, children) = node, let target = ChatFileLink(href) else { return [] }
      let label = children.collect { child -> [String] in
        switch child {
        case .text(let text) where !text.hasPrefix(Self.marker): return [text]
        case .code(let text): return [text]
        default: return []
        }
      }.joined()
      return [UIAccessibilityCustomAction(name: label.isEmpty ? (target.path as NSString).lastPathComponent : label) { [weak self] _ in
        self?.linkHandler?(.string(href), NSRange(location: 0, length: 0), .zero)
        return true
      }]
    }
  }

}

@MainActor
enum ChatTableBleed {
  static func apply(to root: UIView) {
    for table in tables(in: root) {
      hook(table)
      finish(table)
    }
  }

  static func collection(for view: UIView) -> UICollectionView? {
    var current: UIView = view
    while let parent = current.superview {
      if let found = parent as? UICollectionView { return found }
      current = parent
    }
    return nil
  }

  static func markdown(from view: UIView) -> FileMarkdownView? {
    var current: UIView? = view
    while let node = current {
      if let markdown = node as? FileMarkdownView { return markdown }
      current = node.superview
    }
    return nil
  }

  static func isTable(_ view: UIView) -> Bool {
    let name = NSStringFromClass(type(of: view))
    return name.contains("TableView") && !(view is UITableView)
  }

  static func tables(in view: UIView) -> [UIView] {
    var found: [UIView] = []
    if isTable(view) { found.append(view) }
    for subview in view.subviews { found += tables(in: subview) }
    return found
  }

  static func scroll(in table: UIView) -> UIScrollView? {
    table.subviews.compactMap { $0 as? UIScrollView }.first
  }

  static func contains(_ table: UIView, point: CGPoint, from view: UIView, event: UIEvent?) -> Bool {
    if table.point(inside: table.convert(point, from: view), with: event) { return true }
    guard let scroll = scroll(in: table) else { return false }
    return scroll.point(inside: scroll.convert(point, from: view), with: event)
  }

  static func hit(_ table: UIView, point: CGPoint, from view: UIView, event: UIEvent?) -> UIView? {
    let local = table.convert(point, from: view)
    if table.bounds.contains(local) { return table.hitTest(local, with: event) }
    guard let scroll = scroll(in: table) else { return nil }
    return scroll.hitTest(scroll.convert(point, from: view), with: event)
  }

  static func unclip(from view: UIView) {
    var current: UIView? = view
    while let node = current, !(node is UICollectionView) {
      node.clipsToBounds = false
      node.layer.masksToBounds = false
      current = node.superview
    }
  }

  static func contentSpan(_ scroll: UIScrollView) -> CGFloat {
    let frames = scroll.subviews.filter { !($0 is UIImageView) }.map(\.frame)
    guard let minX = frames.map(\.minX).min(), let maxX = frames.map(\.maxX).max() else {
      return scroll.contentSize.width
    }
    return max(0, maxX - minX)
  }

  static func finish(_ table: UIView) {
    guard !finishing else { return }
    guard isTable(table), table.window != nil else { return }
    finishing = true
    defer { finishing = false }
    guard let collection = collection(for: table) else { return }
    guard let markdown = markdown(from: table) ?? table.superview else { return }
    guard let scroll = scroll(in: table) else { return }
    unclip(from: table)
    let span = contentSpan(scroll)
    guard span > markdown.bounds.width + 1 else { return }
    let inCollection = table.convert(table.bounds, to: collection)
    let bled = CGRect(
      x: collection.bounds.minX,
      y: inCollection.minY,
      width: collection.bounds.width,
      height: inCollection.height
    )
    let local = table.convert(bled, from: collection)
    if scroll.frame != local { scroll.frame = local }
    let column = markdown.convert(markdown.bounds, to: collection)
    let left = max(0, column.minX - collection.bounds.minX)
    let right = max(0, collection.bounds.maxX - column.maxX)
    let bodies = scroll.subviews.filter { !($0 is UIImageView) }
    let minX = bodies.map(\.frame.minX).min() ?? 0
    if minX < 0.5 {
      for view in bodies {
        view.frame.origin.x += left
      }
    }
    let width = span + left + right
    if abs(scroll.contentSize.width - width) > 0.5 {
      scroll.contentSize = CGSize(width: width, height: max(scroll.contentSize.height, table.bounds.height))
    }
    scroll.clipsToBounds = true
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.alwaysBounceHorizontal = true
    scroll.isDirectionalLockEnabled = true
    scroll.accessibilityIdentifier = "markdown-table-scroll"
    watch(scroll)
    dump()
  }

  static func hook(_ table: UIView) {
    guard !hooked else { return }
    hooked = true
    let cls: AnyClass = type(of: table)
    let originalSel = #selector(UIView.layoutSubviews)
    let hookSel = #selector(UIView.lody_tableLayoutSubviews)
    guard let hookMethod = class_getInstanceMethod(UIView.self, hookSel) else { return }
    class_addMethod(cls, hookSel, method_getImplementation(hookMethod), method_getTypeEncoding(hookMethod))
    guard let original = class_getInstanceMethod(cls, originalSel),
      let hookedMethod = class_getInstanceMethod(cls, hookSel)
    else { return }
    method_exchangeImplementations(original, hookedMethod)
  }

  static func watch(_ scroll: UIScrollView) {
    #if DEBUG
    guard ProcessInfo.processInfo.arguments.contains("--ui-verify") else { return }
    let id = ObjectIdentifier(scroll)
    if offsetWatches[id] == nil {
      offsetWatches[id] = scroll.observe(\.contentOffset, options: [.new]) { _, _ in
        MainActor.assumeIsolated { dump() }
      }
    }
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
      MainActor.assumeIsolated { dump() }
    }
    #endif
  }

  static func dump() {
    #if DEBUG
    guard ProcessInfo.processInfo.arguments.contains("--ui-verify") else { return }
    guard let window = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    else { return }
    var rows: [[String: Double]] = []
    func walk(_ view: UIView) {
      if let scroll = view as? UIScrollView, scroll.accessibilityIdentifier == "markdown-table-scroll" {
        let frame = scroll.convert(scroll.bounds, to: window)
        rows.append([
          "x": Double(frame.minX),
          "y": Double(frame.minY),
          "width": Double(frame.width),
          "height": Double(frame.height),
          "offsetX": Double(scroll.contentOffset.x),
          "contentWidth": Double(scroll.contentSize.width),
          "boundsWidth": Double(scroll.bounds.width),
          "naturalWidth": Double(contentSpan(scroll)),
          "tableWidth": Double(scroll.bounds.width),
          "contentLeft": Double(scroll.subviews.filter { !($0 is UIImageView) }.map(\.frame.minX).min() ?? 0),
        ])
      }
      for subview in view.subviews { walk(subview) }
    }
    walk(window)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lody-table-bleed.json")
    guard let data = try? JSONSerialization.data(withJSONObject: rows) else { return }
    try? data.write(to: url, options: .atomic)
    #endif
  }

  private static var hooked = false
  private static var finishing = false
  #if DEBUG
  private static var offsetWatches: [ObjectIdentifier: NSKeyValueObservation] = [:]
  private static var timer: Timer?
  #endif
}

extension UIView {
  @objc func lody_tableLayoutSubviews() {
    lody_tableLayoutSubviews()
    MainActor.assumeIsolated {
      ChatTableBleed.finish(self)
    }
  }
}

#if DEBUG
@MainActor
enum ChatContextViewProbe {
  static func record(_ markdown: UIView) {
    guard ProcessInfo.processInfo.arguments.contains("--ui-verify") else { return }
    var grown: [String] = []
    for view in markdown.subviews {
      let name = NSStringFromClass(type(of: view))
      guard name.hasSuffix("CodeView") || ChatTableBleed.isTable(view) else { continue }
      for key in view.layer.animationKeys() ?? [] {
        guard let animation = view.layer.animation(forKey: key) as? CABasicAnimation,
          let path = animation.keyPath, path.hasPrefix("bounds") || path.hasPrefix("position") else { continue }
        grown.append("\(name) \(path) from \(String(describing: animation.fromValue)) frame \(view.frame)")
      }
    }
    guard !grown.isEmpty else { return }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lody-context-view-grown.json")
    let existing = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String] ?? []
    try? JSONSerialization.data(withJSONObject: existing + grown).write(to: url, options: .atomic)
  }
}
#endif

private final class FileLinkButton: UIButton {
  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    bounds.insetBy(dx: min(0, (bounds.width - 44) / 2), dy: min(0, (bounds.height - 44) / 2)).contains(point)
  }
}

enum MaterialFileIcon {
  static func image(for path: String) -> UIImage? {
    let name = "material-\(ChatFileLink.iconName(for: path))"
    let image = UIImage(named: name, in: Bundle(for: LodyKitModule.self), compatibleWith: nil)
      ?? UIImage(named: name, in: .main, compatibleWith: nil)
    return image?.withRenderingMode(.alwaysOriginal)
  }
}
