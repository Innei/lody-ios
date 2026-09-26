#if !LODY_SHARE_EXTENSION
import ExpoModulesCore
#endif
import UIKit

struct LodyListAction: Record {
  @Field var id: String = ""
  @Field var title: String = ""
  @Field var symbol: String = ""
  @Field var tint: String = ""
  @Field var destructive: Bool = false
  @Field var selected: Bool = false
}

struct LodyListValueSegment: Record {
  @Field var text: String = ""
  @Field var tint: String = ""
}

struct LodyListRow: Record {
  @Field var id: String = ""
  @Field var title: String = ""
  @Field var subtitle: String = ""
  @Field var modelName: String = ""
  @Field var value: String = ""
  @Field var progress: Double? = nil
  @Field var valueSegments: [LodyListValueSegment] = []
  @Field var image: String = ""
  @Field var imageAsset: String = ""
  @Field var imageOriginal: Bool = false
  @Field var filePath: String = ""
  @Field var imageTint: String = ""
  @Field var subtitleMono: Bool = false
  @Field var wrapSubtitle: Bool = false
  @Field var unread: Bool = false
  @Field var badge: String = ""
  @Field var diff: [String: Int] = [:]
  @Field var action: Bool = false
  @Field var selected: Bool = false
  @Field var accessibilityValue: String = ""
  @Field var toggle: Bool? = nil
  @Field var navigates: Bool = false
  @Field var disclosure: Bool = false
  @Field var destructive: Bool = false
  @Field var parent: Bool = false
  @Field var parentId: String = ""
  @Field var collapsedValue: String = ""
  @Field var collapsedBadge: String = ""
  @Field var collapsedImageTint: String = ""
  @Field var monogram: String = ""
  @Field var pinned: Bool = false
  @Field var actions: [LodyListAction] = []
  @Field var leadingActions: [LodyListAction] = []
  @Field var menuActions: [LodyListAction] = []
  @Field var options: [LodyListAction] = []
  @Field var preview: String = ""
}

struct LodyListSection: Record {
  @Field var id: String = ""
  @Field var header: String = ""
  @Field var headerValue: String = ""
  @Field var headerActionId: String = ""
  @Field var headerExpanded: Bool? = nil
  @Field var headerProminent: Bool = false
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
