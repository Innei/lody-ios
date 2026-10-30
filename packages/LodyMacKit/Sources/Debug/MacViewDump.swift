#if DEBUG
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
      if let tabs = window.tabbedWindows {
        entry["tabs"] = tabs.map(\.title)
        entry["selectedTab"] = window.tabGroup?.selectedWindow?.title ?? ""
        entry["badges"] = tabs.map { $0.tab.accessoryView?.accessibilityIdentifier() ?? "" }
      }
      if let content = window.contentView { entry["root"] = node(content, visit: MacAccessibilityTree.Visit()) }
      return entry
    }
    let data = try JSONSerialization.data(withJSONObject: ["windows": windows, "accent": MacAccent.current().rawValue, "action": MacVerifyActions.last], options: [.prettyPrinted, .sortedKeys])
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  static func snapshot(_ window: NSWindow, to url: URL) throws {
    guard let frame = window.contentView?.superview ?? window.contentView,
          let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { throw CocoaError(.fileWriteUnknown) }
    frame.cacheDisplay(in: frame.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }

  static func node(_ view: NSView, visit: MacAccessibilityTree.Visit = .init()) -> [String: Any] {
    var entry: [String: Any] = ["class": String(describing: type(of: view)), "frame": frame(view.frame)]
    if !view.accessibilityIdentifier().isEmpty { entry["identifier"] = view.accessibilityIdentifier() }
    if view.isHidden { entry["hidden"] = true }
    if let clip = view as? NSClipView {
      entry["bounds"] = frame(clip.bounds)
      if let scroll = clip.enclosingScrollView { entry["insets"] = [scroll.contentInsets.top, scroll.contentInsets.bottom].map { Double($0) } }
    }
    if let text = text(view), !text.isEmpty { entry["text"] = text }
    if let placeholder = (view as? MacComposerTextView)?.placeholder ?? (view as? NSTextField)?.placeholderString, !placeholder.isEmpty {
      entry["placeholder"] = placeholder
    }
    if let control = view as? NSControl {
      entry["enabled"] = control.isEnabled
      if let window = view.window {
        let rect = view.convert(view.bounds, to: nil)
        entry["inWindow"] = frame(NSRect(x: rect.minX, y: window.frame.height - rect.maxY, width: rect.width, height: rect.height))
      }
    }
    if view.window?.firstResponder === view { entry["firstResponder"] = true }
    let elements = MacAccessibilityTree.elements(of: view, visit: visit).map { element($0, in: view.window, visit: visit) }
    if !elements.isEmpty { entry["elements"] = elements }
    let children = view.subviews.map { node($0, visit: visit) }
    if !children.isEmpty { entry["children"] = children }
    return entry
  }

  private static func element(_ element: MacAccessibilityTree.Element, in window: NSWindow?, visit: MacAccessibilityTree.Visit) -> [String: Any] {
    var entry: [String: Any] = ["role": element.role ?? "", "enabled": element.enabled]
    if let identifier = element.identifier, !identifier.isEmpty { entry["identifier"] = identifier }
    if let label = element.label, !label.isEmpty { entry["label"] = label }
    if element.selected { entry["selected"] = true }
    if let value = element.value { entry["value"] = "\(value)" }
    if let window, let screen = element.frame, screen.minX.isFinite, screen.minY.isFinite, screen.width.isFinite, screen.height.isFinite {
      let rect = window.convertFromScreen(screen)
      entry["inWindow"] = frame(NSRect(x: rect.minX, y: window.frame.height - rect.maxY, width: rect.width, height: rect.height))
    }
    let children = MacAccessibilityTree.children(of: element, visit: visit).map { self.element($0, in: window, visit: visit) }
    if !children.isEmpty { entry["elements"] = children }
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
#endif
