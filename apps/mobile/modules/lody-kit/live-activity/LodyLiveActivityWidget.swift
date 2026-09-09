import ActivityKit
import SwiftUI
import WidgetKit

struct LodyLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LodyActivityAttributes.self) { context in
      LodyLockScreenView(
        state: context.state,
        workspaceSlug: context.attributes.workspaceSlug,
        isStale: context.isStale
      )
    } dynamicIsland: { context in
      island(context)
    }
  }

  private func island(_ context: ActivityViewContext<LodyActivityAttributes>) -> DynamicIsland {
    let state = context.state
    let focus = state.focus
    let slug = context.attributes.workspaceSlug

    return DynamicIsland {
      DynamicIslandExpandedRegion(.leading) {
        if let focus {
          AgentGlyph(text: focus.agentLogoText, size: 34)
            .lodyStale(context.isStale)
        }
      }
      DynamicIslandExpandedRegion(.center) {
        if let focus {
          FocusText(focus: focus, othersCount: state.othersCount, isStale: context.isStale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lodyStale(context.isStale)
        } else {
          Text("没有活跃会话")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      DynamicIslandExpandedRegion(.trailing) {
        if let focus {
          FocusAccessory(focus: focus, needsAttention: state.needsAttention, isStale: context.isStale)
            .lodyStale(context.isStale)
        }
      }
      DynamicIslandExpandedRegion(.bottom) {
        VStack(spacing: 8) {
          if let command = focus?.permissionCommand, focus?.status == .permission {
            CommandStrip(command: command)
          }
          if !state.others.isEmpty {
            OtherRows(items: state.others, workspaceSlug: slug)
          }
        }
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
    .widgetURL(focus.map { LodyActivityAttributes.route(workspaceSlug: slug, sessionId: $0.id) })
  }
}

@main
struct LodyLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    LodyLiveActivityWidget()
  }
}
