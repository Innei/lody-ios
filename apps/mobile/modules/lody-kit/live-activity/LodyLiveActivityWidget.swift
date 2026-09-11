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
      .activityBackgroundTint(context.isStale ? nil : context.state.backgroundTint)
    } dynamicIsland: { context in
      island(context)
    }
  }

  private func island(_ context: ActivityViewContext<LodyActivityAttributes>) -> DynamicIsland {
    let state = context.state
    let focus = state.focus
    let isStale = context.isStale

    return DynamicIsland {
      // The expanded island's corner radius runs under both top regions, so their
      // content is inset off the curve instead of sitting flush against it.
      DynamicIslandExpandedRegion(.leading) {
        if let focus {
          AgentGlyph(kind: focus.agentLogoKind, text: focus.agentLogoText, size: 22)
            .padding(.leading, 10)
            .padding(.top, 8)
            .lodyStale(isStale)
        }
      }
      DynamicIslandExpandedRegion(.trailing) {
        if let focus, !isStale, focus.status != .unread {
          FocusTimer(focus: focus)
            .padding(.trailing, 10)
            .padding(.top, 8)
        }
      }
      // The camera housing splits the top row, so its center is the narrowest track in
      // the whole view. Everything with real text goes into the full-width bottom.
      // The expanded island clips whatever its own height cannot hold, so the bottom
      // carries the focus block and, at most, the pending command; the tap hint and
      // other sessions stay on the Lock Screen, where the card has the height.
      DynamicIslandExpandedRegion(.bottom) {
        VStack(alignment: .leading, spacing: 8) {
          if let focus {
            FocusText(focus: focus, othersCount: state.othersCount, isStale: isStale, copy: state)
            if !isStale, focus.status == .permission, let command = focus.permissionCommand {
              CommandStrip(command: command)
            }
          } else {
            Text(state.emptyLabel)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .lodyStale(isStale)
      }
    } compactLeading: {
      if let focus {
        AgentGlyph(kind: focus.agentLogoKind, text: focus.agentLogoText, size: 20)
          .lodyStale(isStale)
      }
    } compactTrailing: {
      if let focus {
        compactTrailing(state: state, focus: focus, isStale: isStale)
      }
    } minimal: {
      if let focus {
        MinimalSymbol(status: focus.status, isStale: isStale)
          .lodyStale(isStale)
      }
    }
    .widgetURL(focus.map { LodyActivityAttributes.route(workspaceSlug: context.attributes.routeSlug, sessionId: $0.id) })
  }

  @ViewBuilder
  private func compactTrailing(state: LodyActivityAttributes.ContentState, focus: LodyItem, isStale: Bool) -> some View {
    if isStale || focus.status != .running {
      StatusSymbol(status: focus.status, isStale: isStale)
        .lodyStale(isStale)
    } else if state.totalCount > 1 {
      HStack(spacing: 4) {
        StatusSymbol(status: .running)
        Text("\(state.totalCount)")
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 5)
          .background(Capsule().fill(Color.white.opacity(0.16)))
      }
    } else {
      FocusTimer(focus: focus, width: 44)
        .foregroundStyle(.primary)
    }
  }
}

@main
struct LodyLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    LodyLiveActivityWidget()
  }
}
