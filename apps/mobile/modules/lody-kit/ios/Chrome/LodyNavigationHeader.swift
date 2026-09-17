import ObjectiveC
import UIKit

@MainActor
final class LodyNavigationHeader: NSObject {
  private nonisolated(unsafe) static var associationKey: UInt8 = 0

  static func of(_ item: UINavigationItem) -> LodyNavigationHeader {
    if let existing = objc_getAssociatedObject(item, &associationKey) as? LodyNavigationHeader {
      return existing
    }
    let header = LodyNavigationHeader(item: item)
    objc_setAssociatedObject(item, &associationKey, header, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return header
  }

  private(set) weak var item: UINavigationItem?
  private var observations: [NSKeyValueObservation] = []
  private var applying = false

  var title: String? { didSet { apply() } }
  var titleView: UIView? { didSet { apply() } }
  var rightItems: [UIBarButtonItem]? { didSet { apply() } }
  var leftItems: [UIBarButtonItem]? { didSet { apply() } }
  var suspended = false {
    didSet { if !suspended { apply() } }
  }

  private init(item: UINavigationItem) {
    self.item = item
    super.init()
    // screens rewrites every slot on each header prop update and on appear;
    // the write-back must be synchronous because UIKit removes a replaced
    // titleView from the window immediately and only re-adds it on layout.
    observations = [
      item.observe(\.title) { [weak self] _, _ in self?.restore() },
      item.observe(\.titleView) { [weak self] _, _ in self?.restore() },
      item.observe(\.rightBarButtonItems) { [weak self] _, _ in self?.restore() },
      item.observe(\.leftBarButtonItems) { [weak self] _, _ in self?.restore() },
    ]
  }

  private nonisolated func restore() {
    MainActor.assumeIsolated {
      guard !applying else { return }
      apply()
    }
  }

  private func apply() {
    guard !suspended, !applying, let item else { return }
    applying = true
    defer { applying = false }
    if let title, item.title != title { item.title = title }
    if let titleView, item.titleView !== titleView { item.titleView = titleView }
    if let rightItems, item.rightBarButtonItems ?? [] != rightItems { item.rightBarButtonItems = rightItems }
    if let leftItems, item.leftBarButtonItems ?? [] != leftItems { item.leftBarButtonItems = leftItems }
  }
}

@MainActor
enum LodyNavigationHeaderItems {
  typealias Action = @MainActor (String) -> Void

  static func decode(_ json: String, action: @escaping Action) -> [UIBarButtonItem] {
    guard let data = json.data(using: .utf8),
          let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return [] }
    return raw.compactMap { barItem($0, action: action) }
  }

  private static func barItem(_ spec: [String: Any], action: @escaping Action) -> UIBarButtonItem? {
    let type = spec["type"] as? String ?? "button"
    if type == "spacing" {
      return .fixedSpace(CGFloat(spec["spacing"] as? Double ?? 0))
    }
    let id = spec["id"] as? String ?? ""
    let title = spec["title"] as? String
    let image = symbol(spec["icon"])
    let item: UIBarButtonItem
    if type == "menu", let entries = (spec["menu"] as? [String: Any])?["items"] as? [[String: Any]] {
      item = UIBarButtonItem(
        title: title,
        image: image,
        primaryAction: nil,
        menu: menu(entries, title: "", inline: false, action: action)
      )
    } else {
      item = UIBarButtonItem(primaryAction: UIAction(title: title ?? "", image: image) { _ in action(id) })
    }
    item.isEnabled = spec["disabled"] as? Bool != true
    item.accessibilityLabel = spec["accessibilityLabel"] as? String ?? title
    item.accessibilityHint = spec["accessibilityHint"] as? String
    item.accessibilityIdentifier = spec["identifier"] as? String
    if let badge = spec["badge"] as? String, !badge.isEmpty {
      item.badge = .string(badge)
    }
    return item
  }

  private static func menu(
    _ entries: [[String: Any]],
    title: String,
    inline: Bool,
    action: @escaping Action
  ) -> UIMenu {
    UIMenu(
      title: title,
      options: inline ? .displayInline : [],
      children: entries.compactMap { element($0, action: action) }
    )
  }

  private static func element(_ spec: [String: Any], action: @escaping Action) -> UIMenuElement? {
    let title = spec["title"] as? String ?? ""
    let image = symbol(spec["icon"])
    if spec["type"] as? String == "submenu" {
      let entries = spec["items"] as? [[String: Any]] ?? []
      return menu(entries, title: title, inline: spec["inline"] as? Bool == true, action: action)
    }
    if spec["hidden"] as? Bool == true { return nil }
    let id = spec["id"] as? String ?? ""
    var attributes: UIMenuElement.Attributes = []
    if spec["disabled"] as? Bool == true { attributes.insert(.disabled) }
    if spec["destructive"] as? Bool == true { attributes.insert(.destructive) }
    let states: [String: UIMenuElement.State] = ["on": .on, "mixed": .mixed]
    return UIAction(
      title: title,
      subtitle: spec["subtitle"] as? String,
      image: image,
      attributes: attributes,
      state: states[spec["state"] as? String ?? ""] ?? .off
    ) { _ in action(id) }
  }

  private static func symbol(_ value: Any?) -> UIImage? {
    guard let name = value as? String, !name.isEmpty else { return nil }
    return UIImage(systemName: name)
  }
}
