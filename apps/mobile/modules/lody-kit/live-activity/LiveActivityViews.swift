import SwiftUI
import WidgetKit

typealias LodyItem = LodyActivityAttributes.ContentState.Item

struct AgentGlyph: View {
  let text: String
  let size: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
      .fill(Color.secondary.opacity(0.2))
      .frame(width: size, height: size)
      .overlay(
        Text(text)
          .font(.caption.weight(.semibold))
          .minimumScaleFactor(0.5)
          .lineLimit(1)
          .padding(.horizontal, 2)
      )
  }
}

struct StatusDot: View {
  let color: Color

  var body: some View {
    Image(systemName: "circle.fill")
      .font(.system(size: 10))
      .foregroundStyle(color)
  }
}

struct StatusSymbol: View {
  let status: LodyItem.Status

  var body: some View {
    switch status {
    // WidgetKit has no indeterminate spinner: a circular ProgressView ignores
    // controlSize and draws an oversized empty ring, so status is a colored dot.
    case .running:
      StatusDot(color: .blue)
    case .permission, .question:
      StatusDot(color: .orange)
    case .unread:
      Image(systemName: "checkmark")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.green)
    }
  }
}

struct FocusTimer: View {
  let focus: LodyItem

  // A timer Text sizes itself to its whole interval, so an unbounded one running to
  // distantFuture blows the layout out and leaves the entire container unrendered.
  var body: some View {
    Text(timerInterval: focus.updatedDate...Date.distantFuture, countsDown: false)
      .font(.subheadline.monospacedDigit())
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .frame(width: 56, alignment: .leading)
  }
}

struct FocusText: View {
  let focus: LodyItem
  let othersCount: Int
  let isStale: Bool
  let copy: LodyActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(focus.title)
        .font(.headline)
        .lineLimit(1)
      statusLine
    }
  }

  @ViewBuilder
  private var statusLine: some View {
    if isStale {
      Text(copy.staleLabel)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    } else {
      HStack(spacing: 5) {
        StatusSymbol(status: focus.status)
        Text(statusText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if focus.status == .running {
          FocusTimer(focus: focus)
        }
      }
    }
  }

  private var statusText: String {
    if othersCount > 0 {
      return "\(focus.statusLabel) · \(copy.othersLabel(othersCount))"
    }
    return focus.statusLabel
  }
}

struct FocusRow: View {
  let focus: LodyItem
  let othersCount: Int
  let isStale: Bool
  let copy: LodyActivityAttributes.ContentState

  var body: some View {
    HStack(spacing: 12) {
      AgentGlyph(text: focus.agentLogoText, size: 28)
      FocusText(focus: focus, othersCount: othersCount, isStale: isStale, copy: copy)
      Spacer(minLength: 0)
    }
  }
}

struct CommandStrip: View {
  let command: String

  var body: some View {
    Text(command)
      .font(.caption.monospaced())
      .lineLimit(1)
      .truncationMode(.middle)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.secondary.opacity(0.2))
      )
  }
}

struct LodyLockScreenView: View {
  let state: LodyActivityAttributes.ContentState
  let workspaceSlug: String
  let isStale: Bool

  var body: some View {
    content
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
  }

  @ViewBuilder
  private var content: some View {
    if let focus = state.focus {
      FocusRow(focus: focus, othersCount: state.othersCount, isStale: isStale, copy: state)
      .lodyStale(isStale)
      .widgetURL(LodyActivityAttributes.route(workspaceSlug: workspaceSlug, sessionId: focus.id))
    } else {
      Text(state.emptyLabel)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

extension View {
  @ViewBuilder
  func lodyStale(_ isStale: Bool) -> some View {
    if isStale {
      grayscale(1).opacity(0.6)
    } else {
      self
    }
  }
}
