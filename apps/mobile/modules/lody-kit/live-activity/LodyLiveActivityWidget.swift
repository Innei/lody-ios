import ActivityKit
import SwiftUI
import WidgetKit

struct LodyLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LodyActivityAttributes.self) { context in
      LodyLockScreenView(
        state: context.state,
        workspaceSlug: context.attributes.routeSlug,
        isStale: context.isStale
      )
    } dynamicIsland: { context in
      island(context)
    }
  }

  private func island(_ context: ActivityViewContext<LodyActivityAttributes>) -> DynamicIsland {
    let state = context.state
    let focus = state.focus

    return DynamicIsland {
      DynamicIslandExpandedRegion(.leading) {
        if let focus {
          AgentGlyph(text: focus.agentLogoText, size: 20)
            .lodyStale(context.isStale)
        }
      }
      // The camera housing splits the top row, so its center is the narrowest track in
      // the whole view. Everything with real text goes into the full-width bottom.
      DynamicIslandExpandedRegion(.bottom) {
        VStack(alignment: .leading, spacing: 8) {
          if let focus {
            FocusText(focus: focus, othersCount: state.othersCount, isStale: context.isStale)
          } else {
            Text("没有活跃会话")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          // The expanded island clips whatever its own height cannot hold, so the
          // bottom carries the focus block and, at most, the command a pending
          // permission waits on. The status line carries the other sessions as a count.
          if let command = focus?.permissionCommand, focus?.status == .permission {
            CommandStrip(command: command)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lodyStale(context.isStale)
      }
    } compactLeading: {
      if let focus {
        AgentGlyph(text: focus.agentLogoText, size: 20)
          .lodyStale(context.isStale)
      }
    } compactTrailing: {
      if let focus {
        StatusSymbol(status: focus.status)
          .lodyStale(context.isStale)
      }
    } minimal: {
      if let focus {
        StatusSymbol(status: focus.status)
          .lodyStale(context.isStale)
      }
    }
    .widgetURL(focus.map { LodyActivityAttributes.route(workspaceSlug: context.attributes.routeSlug, sessionId: $0.id) })
  }
}

@main
struct LodyLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    LodyLiveActivityWidget()
  }
}
