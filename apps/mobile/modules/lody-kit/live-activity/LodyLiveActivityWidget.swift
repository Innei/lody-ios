import ActivityKit
import SwiftUI
import WidgetKit

struct LodyLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LodyActivityAttributes.self) { context in
      LodyLockScreenView(
        state: context.state,
        workspaceSlug: context.attributes.routeSlug,
        overviewRoute: context.attributes.overviewRoute,
        isStale: context.isStale
      )
      .activityBackgroundTint(.clear)
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
        leading(state: state, focus: focus, size: 22)
          .padding(.leading, 10)
          .padding(.top, 8)
          .lodyStale(isStale)
      }
      DynamicIslandExpandedRegion(.trailing) {
        expandedTrailing(state: state, focus: focus, isStale: isStale)
          .padding(.trailing, 10)
          .padding(.top, 8)
      }
      // The camera housing splits the top row, so its center is the narrowest track in
      // the whole view. Everything with real text goes into the full-width bottom.
      // The expanded island clips whatever its own height cannot hold, so the bottom
      // carries the focus block and, at most, the pending command; the tap hint and
      // other sessions stay on the Lock Screen, where the card has the height.
      DynamicIslandExpandedRegion(.bottom) {
        VStack(alignment: .leading, spacing: 8) {
          if state.showsOverview {
            Text(isStale ? state.staleLabel : state.runningSummary).font(.headline)
            if !isStale, let focus {
              IslandRow(item: focus, state: state)
            }
          } else if let focus {
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
        .background {
          if !isStale, !state.needsAttention {
            JellyGlow(opacity: 0.3)
          }
        }
        .lodyStale(isStale)
      }
    } compactLeading: {
      leading(state: state, focus: focus, size: 20)
        .lodyStale(isStale)
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
    .widgetURL(context.attributes.route(for: state))
  }

  @ViewBuilder
  private func leading(state: LodyState, focus: LodyItem?, size: CGFloat) -> some View {
    if state.showsOverview {
      JellyMark()
    } else if let focus {
      LeadGlyph(item: focus, size: size)
    }
  }

  @ViewBuilder
  private func expandedTrailing(state: LodyState, focus: LodyItem?, isStale: Bool) -> some View {
    if !isStale, state.needsAttention, state.statusCounts.running > 0 {
      Text(state.runningSummary)
        .font(.caption)
        .foregroundStyle(.secondary)
    } else if let focus, !state.showsOverview, state.showsTimer(for: focus, isStale: isStale) {
      WorkTimer(item: focus, font: .system(.title3, design: .rounded).weight(.semibold).monospacedDigit(), width: 64)
    }
  }

  @ViewBuilder
  private func compactTrailing(state: LodyState, focus: LodyItem, isStale: Bool) -> some View {
    if isStale || focus.status == .permission || focus.status == .question || focus.status == .failed {
      StatusSymbol(status: focus.status, isStale: isStale)
        .lodyStale(isStale)
    } else if state.showsOverview {
      HStack(spacing: 4) {
        StatusSymbol(status: .running)
        Text("\(state.activeCount)")
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 5)
          .background(Capsule().fill(Color.white.opacity(0.16)))
      }
    } else if state.showsTimer(for: focus, isStale: false) {
      WorkTimer(item: focus, font: .subheadline.weight(.semibold).monospacedDigit(), width: 44)
        .foregroundStyle(.primary)
    } else {
      StatusSymbol(status: focus.status)
    }
  }
}

@main
struct LodyLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    LodyLiveActivityWidget()
  }
}
