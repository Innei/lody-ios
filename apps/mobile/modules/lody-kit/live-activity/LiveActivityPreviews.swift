#if DEBUG
import ActivityKit
import SwiftUI
import WidgetKit

#Preview("Lock Screen", as: .content, using: LiveActivityFixtures.attributes) {
  LodyLiveActivityWidget()
} contentStates: {
  LiveActivityFixtures.running
  LiveActivityFixtures.single
  LiveActivityFixtures.permission
  LiveActivityFixtures.question
  LiveActivityFixtures.unknownAgent
  LiveActivityFixtures.brands
  LiveActivityFixtures.done
  LiveActivityFixtures.failed
  LiveActivityFixtures.doneMany
}

#Preview("Island Expanded", as: .dynamicIsland(.expanded), using: LiveActivityFixtures.attributes) {
  LodyLiveActivityWidget()
} contentStates: {
  LiveActivityFixtures.running
  LiveActivityFixtures.permission
  LiveActivityFixtures.question
  LiveActivityFixtures.done
}

#Preview("Island Compact", as: .dynamicIsland(.compact), using: LiveActivityFixtures.attributes) {
  LodyLiveActivityWidget()
} contentStates: {
  LiveActivityFixtures.running
  LiveActivityFixtures.single
  LiveActivityFixtures.permission
  LiveActivityFixtures.done
}

#Preview("Island Minimal", as: .dynamicIsland(.minimal), using: LiveActivityFixtures.attributes) {
  LodyLiveActivityWidget()
} contentStates: {
  LiveActivityFixtures.single
  LiveActivityFixtures.permission
}
#endif
