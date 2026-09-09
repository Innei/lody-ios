import ActivityKit
import SwiftUI
import WidgetKit

struct PlaceholderAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {}
}

struct LodyPlaceholderActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: PlaceholderAttributes.self) { _ in
      EmptyView()
    } dynamicIsland: { _ in
      DynamicIsland {
        DynamicIslandExpandedRegion(.center) { EmptyView() }
      } compactLeading: {
        EmptyView()
      } compactTrailing: {
        EmptyView()
      } minimal: {
        EmptyView()
      }
    }
  }
}

@main
struct LodyLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    LodyPlaceholderActivityWidget()
  }
}
