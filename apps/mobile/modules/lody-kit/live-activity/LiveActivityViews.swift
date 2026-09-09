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

struct StatusSymbol: View {
  let status: LodyItem.Status

  var body: some View {
    switch status {
    case .running:
      ProgressView()
        .progressViewStyle(.circular)
        .controlSize(.mini)
        .tint(.blue)
    case .permission, .question:
      Circle()
        .fill(Color.orange)
        .frame(width: 10, height: 10)
    case .unread:
      Image(systemName: "checkmark")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.green)
    }
  }
}

struct FocusText: View {
  let focus: LodyItem
  let othersCount: Int
  let isStale: Bool

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
      Text("已断开")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    } else {
      HStack(spacing: 5) {
        StatusSymbol(status: focus.status)
        Text(statusText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }

  private var statusText: String {
    if othersCount > 0 {
      return "\(focus.statusLabel) · 还有 \(othersCount) 个在跑"
    }
    return focus.statusLabel
  }
}

struct FocusAccessory: View {
  let focus: LodyItem
  let needsAttention: Bool
  let isStale: Bool

  var body: some View {
    if focus.status == .running, !isStale {
      Text(
        timerInterval: focus.updatedDate...Date.distantFuture,
        countsDown: false
      )
      .font(.title2.monospacedDigit())
      .foregroundStyle(.blue)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .multilineTextAlignment(.trailing)
      .frame(width: 88, alignment: .trailing)
    } else {
      Text("查看")
        .font(.caption.weight(.semibold))
        .foregroundStyle(pillColor)
        .padding(.vertical, 5)
        .frame(width: 88)
        .background(Capsule().fill(pillColor.opacity(0.18)))
    }
  }

  private var pillColor: Color {
    needsAttention && !isStale ? .orange : .secondary
  }
}

struct FocusRow: View {
  let focus: LodyItem
  let othersCount: Int
  let needsAttention: Bool
  let isStale: Bool
  let glyphSize: CGFloat

  var body: some View {
    HStack(spacing: 12) {
      AgentGlyph(text: focus.agentLogoText, size: glyphSize)
      FocusText(focus: focus, othersCount: othersCount, isStale: isStale)
      Spacer(minLength: 8)
      FocusAccessory(focus: focus, needsAttention: needsAttention, isStale: isStale)
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

struct OtherRows: View {
  let items: [LodyItem]
  let workspaceSlug: String

  var body: some View {
    VStack(spacing: 6) {
      Divider()
      ForEach(items, id: \.id) { item in
        Link(destination: LodyActivityAttributes.route(workspaceSlug: workspaceSlug, sessionId: item.id)) {
          HStack(spacing: 8) {
            AgentGlyph(text: item.agentLogoText, size: 20)
            Text(item.title)
              .font(.subheadline)
              .lineLimit(1)
            Spacer(minLength: 8)
            StatusSymbol(status: item.status)
          }
        }
      }
    }
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
      FocusRow(
        focus: focus,
        othersCount: state.othersCount,
        needsAttention: state.needsAttention,
        isStale: isStale,
        glyphSize: 34
      )
      .lodyStale(isStale)
      .widgetURL(LodyActivityAttributes.route(workspaceSlug: workspaceSlug, sessionId: focus.id))
    } else {
      Text("没有活跃会话")
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
