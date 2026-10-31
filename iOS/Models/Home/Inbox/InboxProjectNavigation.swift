import CoreGraphics
import Foundation

struct InboxProjectChip: Equatable, Sendable {
  var id: String
  var title: String
  var image = ""
  var monogram = ""
  var symbol = ""
  var state: SessionState?
  var count = 0
}

struct InboxIndexItem: Equatable, Sendable {
  var id: String
  var title: String
  var symbol = ""
  var image = ""
  var monogram = ""
  var dot: SessionState?
}

struct InboxIndexVisibility {
  private(set) var shown = false
  private(set) var enabled = false
  private var scrolling = false
  private var touching = false

  mutating func setEnabled(_ value: Bool) {
    enabled = value
    if !value { shown = false }
  }

  mutating func scrollBegan() {
    scrolling = true
    if enabled { shown = true }
  }

  mutating func scrollEnded() -> Bool {
    scrolling = false
    return shown && !touching
  }

  mutating func touchBegan() {
    touching = true
    scrolling = false
  }

  mutating func touchEnded() -> Bool {
    touching = false
    return shown
  }

  mutating func hideFired() {
    if !scrolling && !touching { shown = false }
  }
}

enum InboxProjectIndexModel {
  static let itemPitch: CGFloat = 44

  static func items(sectionIds: [String], chips: [InboxProjectChip]) -> [InboxIndexItem] {
    let byId = Dictionary(chips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return sectionIds.compactMap { id in
      if id == InboxSections.pinnedId {
        return InboxIndexItem(id: id, title: String(localized: "inbox.section.pinned", bundle: .lody), symbol: "pin.fill")
      }
      guard let chip = byId[id] else { return nil }
      return InboxIndexItem(id: id, title: chip.title, symbol: chip.symbol, image: chip.image, monogram: chip.monogram, dot: chip.state)
    }
  }

  static func pitch(count: Int, available: CGFloat) -> CGFloat {
    guard count > 0 else { return itemPitch }
    return min(itemPitch, available / CGFloat(count))
  }

  static func item(at y: CGFloat, count: Int, pitch: CGFloat) -> Int {
    guard count > 0, pitch > 0 else { return 0 }
    return min(count - 1, max(0, Int((y / pitch).rounded(.down))))
  }

  static func current(_ tops: [(id: String, y: CGFloat)], edge: CGFloat) -> String? {
    tops.last { $0.y <= edge + 0.5 }?.id ?? tops.first?.id
  }
}
