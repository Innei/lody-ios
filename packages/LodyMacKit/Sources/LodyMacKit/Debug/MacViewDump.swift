import AppKit

@MainActor
enum MacViewDump {
  static func write(to url: URL) throws {
    let windows = NSApp.windows.filter(\.isVisible).map { window -> [String: Any] in
      var entry: [String: Any] = [
        "title": window.title,
        "identifier": window.identifier?.rawValue ?? "",
        "key": window.isKeyWindow,
        "appearance": window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? "",
        "frame": frame(window.frame),
      ]
      if let tabs = window.tabbedWindows { entry["tabs"] = tabs.map(\.title) }
      if let content = window.contentView { entry["root"] = node(content) }
      return entry
    }
    let data = try JSONSerialization.data(withJSONObject: ["windows": windows], options: [.prettyPrinted, .sortedKeys])
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  private static func node(_ view: NSView) -> [String: Any] {
    var entry: [String: Any] = ["class": String(describing: type(of: view)), "frame": frame(view.frame)]
    if !view.accessibilityIdentifier().isEmpty { entry["identifier"] = view.accessibilityIdentifier() }
    if view.isHidden { entry["hidden"] = true }
    if let text = text(view), !text.isEmpty { entry["text"] = text }
    if let control = view as? NSControl { entry["enabled"] = control.isEnabled }
    if view.window?.firstResponder === view { entry["firstResponder"] = true }
    let children = view.subviews.map(node)
    if !children.isEmpty { entry["children"] = children }
    return entry
  }

  private static func text(_ view: NSView) -> String? {
    if let button = view as? NSButton { return button.title }
    if let field = view as? NSTextField { return field.stringValue }
    if let textView = view as? NSTextView { return textView.string }
    return nil
  }

  private static func frame(_ rect: NSRect) -> [Double] {
    [rect.origin.x, rect.origin.y, rect.width, rect.height].map { Double($0) }
  }
}
