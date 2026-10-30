#if DEBUG
import AppKit

// SwiftUI controls are accessibility nodes, not NSControls, so in-process checks read and press them here.
// SwiftUI builds those nodes only after an assistive client asks for enhanced UI, and its private
// AccessibilityNode class answers the accessibility selectors without conforming to NSAccessibilityProtocol.
@MainActor
enum MacAccessibilityTree {
  @MainActor
  struct Element {
    let object: NSObject

    private func read(_ getter: String, key: String) -> Any? {
      object.responds(to: Selector(getter)) ? object.value(forKey: key) : nil
    }

    var identifier: String? { read("accessibilityIdentifier", key: "accessibilityIdentifier") as? String }
    var label: String? { read("accessibilityLabel", key: "accessibilityLabel") as? String }
    var role: String? { read("accessibilityRole", key: "accessibilityRole") as? String }
    var value: Any? { read("accessibilityValue", key: "accessibilityValue") }
    var enabled: Bool { (read("isAccessibilityEnabled", key: "accessibilityEnabled") as? Bool) ?? true }
    var selected: Bool { (read("isAccessibilitySelected", key: "accessibilitySelected") as? Bool) ?? false }
    var frame: NSRect? { (read("accessibilityFrame", key: "accessibilityFrame") as? NSValue)?.rectValue }

    var children: [Element] { MacAccessibilityTree.wrap(read("accessibilityChildren", key: "accessibilityChildren") as? [Any]) }

    func press() -> Bool {
      let selector = #selector(NSAccessibilityProtocol.accessibilityPerformPress)
      guard object.responds(to: selector) else { return false }
      _ = object.perform(selector)
      return true
    }
  }

  // Lists and forms reparent rows through proxies, so the same node can appear under several parents.
  @MainActor
  final class Visit {
    private var seen = Set<ObjectIdentifier>()

    func first(_ element: Element) -> Bool { seen.insert(ObjectIdentifier(element.object)).inserted }
  }

  static func enable() {
    for attribute in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
      NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: attribute))
    }
  }

  static func elements(of view: NSView, visit: Visit) -> [Element] {
    wrap(view.accessibilityChildren()).filter(visit.first)
  }

  static func children(of element: Element, visit: Visit) -> [Element] {
    element.children.filter(visit.first)
  }

  static func all(in view: NSView) -> [Element] {
    let visit = Visit()
    func walk(_ element: Element) -> [Element] { [element] + children(of: element, visit: visit).flatMap(walk) }
    func views(_ view: NSView) -> [Element] { elements(of: view, visit: visit).flatMap(walk) + view.subviews.flatMap(views) }
    return views(view)
  }

  static func press(_ text: String, in view: NSView) -> Bool {
    let target = all(in: view).first { element in
      element.enabled && (element.identifier == text || element.label == text)
    }
    guard let target else { return false }
    if target.role == NSAccessibility.Role.staticText.rawValue, selectRow(containing: target, in: view) { return true }
    return target.press()
  }

  // SwiftUI List rows expose only their text; choosing one means selecting the backing table row.
  private static func selectRow(containing element: Element, in view: NSView) -> Bool {
    guard let window = view.window, let screen = element.frame else { return false }
    let point = window.convertPoint(fromScreen: NSPoint(x: screen.midX, y: screen.midY))
    for table in tables(in: view) {
      let row = table.row(at: table.convert(point, from: nil))
      guard row >= 0 else { continue }
      table.selectRowIndexes([row], byExtendingSelection: false)
      return true
    }
    return false
  }

  private static func tables(in view: NSView) -> [NSTableView] {
    ((view as? NSTableView).map { [$0] } ?? []) + view.subviews.flatMap(tables)
  }

  fileprivate static func wrap(_ children: [Any]?) -> [Element] {
    (children ?? []).compactMap { child in
      guard !(child is NSView), let object = child as? NSObject else { return nil }
      return Element(object: object)
    }
  }
}
#endif
