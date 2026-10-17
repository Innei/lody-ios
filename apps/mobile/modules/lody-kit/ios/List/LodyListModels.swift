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
  @Field var status: String = ""
  @Field var trailingSymbol: String = ""
  @Field var trailingSymbolLabel: String = ""
  @Field var valueSymbol: String = ""
}

struct LodyListVisualItem: Record {
  @Field var id: String = ""
  @Field var label: String = ""
  @Field var value: String = ""
  @Field var amount: Double = 0
  @Field var detail: String = ""
  @Field var percent: String = ""
  @Field var fraction: Double = 0
  @Field var caption: String = ""
  @Field var accessibilityLabel: String = ""
  @Field var accessibilityValue: String = ""
  @Field var pace: Double? = nil
  @Field var tone: String = ""
  @Field var cost: Double? = nil
  @Field var axisLabel: String = ""
}

struct LodyListVisual: Record {
  @Field var type: String = ""
  @Field var title: String = ""
  @Field var summary: String = ""
  @Field var dimmed: Bool = false
  @Field var metrics: [String] = []
  @Field var costTitle: String = ""
  @Field var costSummary: String = ""
  @Field var items: [LodyListVisualItem] = []
}

struct LodyListNotice: Record {
  @Field var symbol: String = ""
  @Field var text: String = ""
  @Field var tint: String = ""
  @Field var actionSymbol: String = ""
  @Field var actionLabel: String = ""
}

struct LodyListUnavailable: Record {
  @Field var symbol: String = ""
  @Field var title: String = ""
  @Field var message: String = ""
  @Field var actionTitle: String = ""
}

struct LodyListSection: Record {
  @Field var id: String = ""
  @Field var header: String = ""
  @Field var headerValue: String = ""
  @Field var headerActionId: String = ""
  @Field var headerExpanded: Bool? = nil
  @Field var headerProminent: Bool = false
  @Field var headerStatus: String = ""
  @Field var footer: String = ""
  @Field var rows: [LodyListRow] = []
  @Field var visual: LodyListVisual? = nil
}

// Both native list hosts share hierarchy, while keeping their own layout and selection.
extension LodyListSection {
  @MainActor
  static func prepareForFlatSnapshot<Item: Hashable & Sendable>(
    in dataSource: UICollectionViewDiffableDataSource<String, Item>
  ) {
    // The main snapshot omits collapsed children, but UIKit still owns them in
    // its section snapshots. Replace that hierarchy explicitly before returning
    // to flat updates; rebasing a flat snapshot can insert those children twice.
    let visible = dataSource.snapshot()
    for id in visible.sectionIdentifiers {
      let snapshot = dataSource.snapshot(for: id)
      guard snapshot.items.count != snapshot.rootItems.count else { continue }
      var flat = NSDiffableDataSourceSectionSnapshot<Item>()
      flat.append(visible.itemIdentifiers(inSection: id))
      dataSource.apply(flat, to: id, animatingDifferences: false)
    }
  }

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

extension LodyListSection {
  // Record fields are reference boxes; a copy made by assignment would share
  // them, so the synthetic row goes into a freshly built section.
  func prepending(_ row: LodyListRow) -> LodyListSection {
    var copy = LodyListSection()
    copy.id = id
    copy.header = header
    copy.headerValue = headerValue
    copy.headerActionId = headerActionId
    copy.headerExpanded = headerExpanded
    copy.headerProminent = headerProminent
    copy.headerStatus = headerStatus
    copy.footer = footer
    copy.visual = visual
    copy.rows = [row] + rows
    return copy
  }

  static func synthetic(id: String, rowID: String, visual: LodyListVisual? = nil) -> LodyListSection {
    var row = LodyListRow()
    row.id = rowID
    var section = LodyListSection()
    section.id = id
    section.visual = visual
    section.rows = [row]
    return section
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
