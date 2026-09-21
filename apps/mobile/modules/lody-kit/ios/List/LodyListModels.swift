import ExpoModulesCore
import UIKit

@Record
struct LodyListAction {
  var id: String = ""
  var title: String = ""
  var symbol: String = ""
  var tint: String = ""
  var destructive: Bool = false
  var selected: Bool = false
}

@Record
struct LodyListValueSegment {
  var text: String = ""
  var tint: String = ""
}

@Record
struct LodyListRow {
  var id: String = ""
  var title: String = ""
  var subtitle: String = ""
  var modelName: String = ""
  var value: String = ""
  var progress: Double? = nil
  var valueSegments: [LodyListValueSegment] = []
  var image: String = ""
  var imageAsset: String = ""
  var imageOriginal: Bool = false
  var filePath: String = ""
  var imageTint: String = ""
  var subtitleMono: Bool = false
  var unread: Bool = false
  var badge: String = ""
  var diff: [String: Int] = [:]
  var action: Bool = false
  var selected: Bool = false
  var accessibilityValue: String = ""
  var toggle: Bool? = nil
  var navigates: Bool = false
  var disclosure: Bool = false
  var destructive: Bool = false
  var parent: Bool = false
  var parentId: String = ""
  var collapsedValue: String = ""
  var collapsedBadge: String = ""
  var collapsedImageTint: String = ""
  var monogram: String = ""
  var pinned: Bool = false
  var actions: [LodyListAction] = []
  var leadingActions: [LodyListAction] = []
  var menuActions: [LodyListAction] = []
  var options: [LodyListAction] = []
  var preview: String = ""
}

struct LodyListSection: Record {
  @Field var id: String = ""
  @Field var header: String = ""
  @Field var headerValue: String = ""
  @Field var headerActionId: String = ""
  @Field var headerExpanded: Bool? = nil
  @Field var footer: String = ""
  @Field var rows: [LodyListRow] = []
}

// Both native list hosts share hierarchy, while keeping their own layout and selection.
extension LodyListSection {
  func outlineSnapshot<Item: Hashable & Sendable>(
    collapsed: Set<String>, itemID: (String) -> Item
  ) -> NSDiffableDataSourceSectionSnapshot<Item> {
    var snapshot = NSDiffableDataSourceSectionSnapshot<Item>()
    let sectionParent = rows.first.flatMap { $0.parent ? itemID($0.id) : nil }
    for row in rows {
      let item = itemID(row.id)
      let parent = row.parentId.isEmpty ? sectionParent : itemID(row.parentId)
      let availableParent = parent.flatMap { snapshot.contains($0) ? $0 : nil }
      snapshot.append([item], to: availableParent)
    }
    for row in rows {
      if row.parent {
        if headerExpanded ?? true { snapshot.expand([itemID(row.id)]) }
      } else if !row.collapsedValue.isEmpty && !collapsed.contains(row.id) {
        snapshot.expand([itemID(row.id)])
      }
    }
    return snapshot
  }
}

extension LodyListRow {
  func displayingCollapsed(_ collapsed: Bool) -> LodyListRow {
    guard collapsed, !collapsedValue.isEmpty else { return self }
    var copy = self
    copy.value = collapsedValue
    copy.badge = collapsedBadge
    copy.imageTint = collapsedImageTint
    return copy
  }
}
