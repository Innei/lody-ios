import SwiftUI
import WidgetKit

typealias LodyItem = LodyActivityAttributes.ContentState.Item

struct AgentGlyph: View {
  let kind: String
  let text: String
  let size: CGFloat

  static let kinds: Set<String> = [
    "claude", "codex", "kimi", "grok", "deepseek", "minimax", "glm", "mimo", "opencode", "gemini", "openai",
  ]
  private static let aliases = ["claude-p": "claude", "kimi-code": "kimi"]

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
      .fill(image == nil ? Color.secondary.opacity(0.2) : Color.white)
      .frame(width: size, height: size)
      .overlay(mark)
  }

  private var image: String? {
    let key = kind.lowercased()
    let canonical = Self.aliases[key] ?? key
    return Self.kinds.contains(canonical) ? "lody-agent-\(canonical)" : nil
  }

  @ViewBuilder
  private var mark: some View {
    if let image {
      Image(image)
        .resizable()
        .renderingMode(.template)
        .foregroundStyle(.black)
        .padding(size * 0.2)
    } else {
      Text(text)
        .font(.caption.weight(.semibold))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .padding(.horizontal, 2)
    }
  }
}

struct StatusSymbol: View {
  let status: LodyItem.Status
  var isStale = false

  var body: some View {
    // WidgetKit has no indeterminate spinner: a circular ProgressView ignores
    // controlSize and draws an oversized empty ring, so running is a pulsing dot.
    switch (isStale, status) {
    case (true, _):
      Image(systemName: "wifi.slash")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    case (_, .running):
      Image(systemName: "circle.fill")
        .font(.system(size: 10))
        .foregroundStyle(.blue)
        .symbolEffect(.pulse)
    case (_, .permission):
      Image(systemName: "exclamationmark.circle.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.orange)
    case (_, .question):
      Image(systemName: "questionmark.circle.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.orange)
    case (_, .unread):
      Image(systemName: "checkmark.circle.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.blue)
    }
  }
}

struct MinimalSymbol: View {
  let status: LodyItem.Status
  let isStale: Bool

  var body: some View {
    if isStale || status != .running {
      StatusSymbol(status: status, isStale: isStale)
    } else {
      Circle()
        .strokeBorder(Color.blue, lineWidth: 3)
        .frame(width: 14, height: 14)
    }
  }
}

struct FocusTimer: View {
  let focus: LodyItem
  var width: CGFloat = 56

  // A timer Text sizes itself to its whole interval, so an unbounded one running to
  // distantFuture blows the layout out and leaves the entire container unrendered.
  var body: some View {
    Text(timerInterval: focus.updatedDate...Date.distantFuture, countsDown: false)
      .font(.subheadline.monospacedDigit())
      .foregroundStyle(.secondary)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .multilineTextAlignment(.trailing)
      .frame(width: width, alignment: .trailing)
  }
}

struct StatusPill: View {
  let status: LodyItem.Status
  let label: String

  var body: some View {
    HStack(spacing: 4) {
      StatusSymbol(status: status)
      Text(label)
        .font(.footnote.weight(.medium))
        .lineLimit(1)
    }
    .foregroundStyle(tint)
    .padding(.horizontal, 8)
    .padding(.vertical, 3)
    .background(Capsule().fill(tint.opacity(0.18)))
  }

  private var tint: Color {
    switch status {
    case .permission, .question: .orange
    case .running, .unread: .blue
    }
  }
}

struct FocusText: View {
  let focus: LodyItem
  let othersCount: Int
  let isStale: Bool
  let copy: LodyActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(focus.title)
        .font(.headline)
        .lineLimit(1)
      statusLine
    }
  }

  @ViewBuilder
  private var statusLine: some View {
    if isStale {
      HStack(spacing: 5) {
        StatusSymbol(status: focus.status, isStale: true)
        Text(copy.staleLabel)
        Text("·")
        Text(copy.lastSyncLabel) + Text(" ") + Text(focus.updatedDate, style: .relative)
      }
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    } else if focus.status == .running {
      HStack(spacing: 5) {
        StatusSymbol(status: .running)
        Text(runningText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    } else {
      StatusPill(status: focus.status, label: focus.statusLabel)
    }
  }

  private var runningText: String {
    if othersCount > 0 {
      return "\(focus.statusLabel) · \(copy.othersLabel(othersCount))"
    }
    return focus.statusLabel
  }
}

struct FocusRow: View {
  let state: LodyActivityAttributes.ContentState
  let focus: LodyItem
  let isStale: Bool
  let glyphSize: CGFloat

  var body: some View {
    HStack(spacing: 12) {
      AgentGlyph(kind: focus.agentLogoKind, text: focus.agentLogoText, size: glyphSize)
      FocusText(focus: focus, othersCount: state.othersCount, isStale: isStale, copy: state)
      Spacer(minLength: 4)
      if !isStale, focus.status != .unread {
        FocusTimer(focus: focus)
      }
    }
  }
}

struct OthersList: View {
  let items: [LodyItem]

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      ForEach(items, id: \.id) { item in
        HStack(spacing: 8) {
          StatusSymbol(status: item.status)
          Text(item.title)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer(minLength: 4)
          if item.status != .unread {
            FocusTimer(focus: item)
          }
        }
      }
    }
    .padding(.top, 8)
    .overlay(alignment: .top) { Divider().opacity(0.6) }
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
          .fill(Color.orange.opacity(0.16))
      )
  }
}

struct AttentionBlock: View {
  let focus: LodyItem
  let copy: LodyActivityAttributes.ContentState

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if let command = focus.permissionCommand, focus.status == .permission {
        CommandStrip(command: command)
      }
      Text(copy.openHintLabel)
        .font(.caption)
        .foregroundStyle(.tertiary)
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
      .padding(.vertical, 14)
  }

  @ViewBuilder
  private var content: some View {
    if let focus = state.focus {
      VStack(alignment: .leading, spacing: 10) {
        FocusRow(state: state, focus: focus, isStale: isStale, glyphSize: 36)
        if !isStale, state.needsAttention {
          AttentionBlock(focus: focus, copy: state)
        } else if !state.others.isEmpty {
          OthersList(items: state.others)
        }
      }
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

extension LodyActivityAttributes.ContentState {
  var backgroundTint: Color? {
    needsAttention ? Color.orange.opacity(0.22) : nil
  }
}

extension View {
  @ViewBuilder
  func lodyStale(_ isStale: Bool) -> some View {
    if isStale {
      opacity(0.7)
    } else {
      self
    }
  }
}
