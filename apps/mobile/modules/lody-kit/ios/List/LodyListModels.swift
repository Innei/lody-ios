import ExpoModulesCore

@Record
struct LodyListAction {
  var id: String = ""
  var title: String = ""
  var symbol: String = ""
  var tint: String = ""
  var destructive: Bool = false
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
  var monogram: String = ""
  var pinned: Bool = false
  var actions: [LodyListAction] = []
  var leadingActions: [LodyListAction] = []
  var menuActions: [LodyListAction] = []
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
