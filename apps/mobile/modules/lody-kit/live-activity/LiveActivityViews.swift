import SwiftUI
import WidgetKit

typealias LodyItem = LodyActivityAttributes.ContentState.Item
typealias LodyState = LodyActivityAttributes.ContentState

enum LodyTone {
  static let blue = Color(red: 0.24, green: 0.36, blue: 0.86)
  static let teal = Color(red: 0.16, green: 0.73, blue: 0.61)
  static let glow = LinearGradient(colors: [blue, teal], startPoint: .topLeading, endPoint: .bottomTrailing)
}

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

struct DoneGlyph: View {
  let size: CGFloat
  var failed = false

  var body: some View {
    Circle()
      .fill(failed ? Color.red : Color.blue)
      .frame(width: size, height: size)
      .overlay(
        Image(systemName: failed ? "xmark" : "checkmark")
          .font(.system(size: size * 0.48, weight: .bold))
          .foregroundStyle(.white)
      )
  }
}

struct LeadGlyph: View {
  let item: LodyItem
  let size: CGFloat

  var body: some View {
    if item.isDone {
      DoneGlyph(size: size, failed: item.status == .failed)
    } else {
      AgentGlyph(kind: item.agentLogoKind, text: item.agentLogoText, size: size)
    }
  }
}

struct GlyphStack: View {
  let items: [LodyItem]
  let size: CGFloat

  var body: some View {
    ZStack(alignment: .topLeading) {
      ForEach(Array(items.prefix(2).enumerated()), id: \.offset) { index, item in
        AgentGlyph(kind: item.agentLogoKind, text: item.agentLogoText, size: size * 0.72)
          .offset(x: CGFloat(index) * size * 0.28, y: CGFloat(index) * size * 0.28)
      }
    }
    .frame(width: size, height: size, alignment: .topLeading)
  }
}

// The jellyfish dissolves into the system glass through a radial mask, so no
// edge of the artwork ever reads as a badge or a card on top of the container.
// ActivityKit replaces an image whose pixels exceed its frame with a grey box, so
// the asset ships at exactly this point size in 1x/2x/3x and is never drawn larger.
struct JellyGlow: View {
  @AppStorage(LodyActivityIcon.key, store: LodyActivityIcon.defaults) private var appIcon = "default"
  static let pointSize: CGFloat = 120
  var opacity: Double = 0.55
  private var size: CGFloat { Self.pointSize }

  var body: some View {
    Image(LodyActivityIcon.asset(name: appIcon, mark: false))
      .resizable()
      .scaledToFit()
      .frame(width: size, height: size)
      .mask(
        RadialGradient(
          colors: [.black, .black.opacity(0.45), .clear],
          center: UnitPoint(x: 0.45, y: 0.4),
          startRadius: 0,
          endRadius: size * 0.5
        )
      )
      .opacity(opacity)
      .accessibilityHidden(true)
      .allowsHitTesting(false)
  }
}

struct JellyMark: View {
  @AppStorage(LodyActivityIcon.key, store: LodyActivityIcon.defaults) private var appIcon = "default"
  static let pointSize: CGFloat = 22

  var body: some View {
    Image(LodyActivityIcon.asset(name: appIcon, mark: true))
      .resizable()
      .frame(width: Self.pointSize, height: Self.pointSize)
      .accessibilityHidden(true)
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
        .font(.system(size: 9))
        .foregroundStyle(LodyTone.glow)
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
    case (_, .failed):
      Image(systemName: "xmark.circle.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.red)
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
        .strokeBorder(LodyTone.glow, lineWidth: 3)
        .frame(width: 14, height: 14)
    }
  }
}

struct WorkTimer: View {
  let item: LodyItem
  var font: Font = .subheadline.monospacedDigit()
  var width: CGFloat = 56

  var body: some View {
    // A timer Text sizes itself to its whole interval, so an unbounded one running to
    // distantFuture blows the layout out and leaves the entire container unrendered.
    Group {
      if let end = item.completedDate {
        Text(timerInterval: item.startDate...max(end, item.startDate), pauseTime: end, countsDown: false)
      } else {
        Text(timerInterval: item.startDate...Date.distantFuture, countsDown: false)
      }
    }
    .font(font)
    .lineLimit(1)
    .minimumScaleFactor(0.7)
    .multilineTextAlignment(.trailing)
    .frame(width: width, alignment: .trailing)
  }
}

struct HeroTimer: View {
  let item: LodyItem
  let caption: String

  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      WorkTimer(item: item, font: .system(.title2, design: .rounded).weight(.semibold).monospacedDigit(), width: 78)
      Text(caption)
        .font(.caption2.weight(.medium))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }
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
    case .failed: .red
    }
  }
}

struct FocusText: View {
  let focus: LodyItem
  let othersCount: Int
  let isStale: Bool
  let copy: LodyState

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
    } else if focus.isDone {
      HStack(spacing: 5) {
        StatusPill(status: focus.status, label: focus.statusLabel)
        Text(focus.updatedDate, style: .relative)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    } else {
      HStack(spacing: 5) {
        StatusPill(status: focus.status, label: focus.statusLabel)
        if copy.statusCounts.running > 0 {
          Text(copy.runningSummary)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
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
  let state: LodyState
  let focus: LodyItem
  let isStale: Bool
  let glyphSize: CGFloat

  var body: some View {
    HStack(spacing: 12) {
      LeadGlyph(item: focus, size: glyphSize)
      FocusText(focus: focus, othersCount: state.othersCount, isStale: isStale, copy: state)
      Spacer(minLength: 4)
      if state.showsTimer(for: focus, isStale: isStale) {
        HeroTimer(item: focus, caption: state.timerCaption(for: focus))
      }
    }
  }
}

struct OverviewHeader: View {
  let state: LodyState
  let items: [LodyItem]
  let isStale: Bool

  var body: some View {
    HStack(spacing: 12) {
      if state.isCompleted {
        DoneGlyph(size: 36, failed: state.allFailed)
      } else {
        GlyphStack(items: items, size: 36)
      }
      VStack(alignment: .leading, spacing: 3) {
        Text(headline)
          .font(.headline)
          .lineLimit(1)
        HStack(spacing: 5) {
          StatusSymbol(status: headerStatus, isStale: isStale)
          Text(subline)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
  }

  private var headerStatus: LodyItem.Status {
    if !state.isCompleted { return .running }
    return state.allFailed ? .failed : .unread
  }

  private var headline: String {
    if isStale { return state.staleLabel }
    if state.allFailed { return state.failedSummary(state.completedItems.count) }
    return state.isCompleted ? state.completedSummary(state.completedItems.count) : state.runningSummary
  }

  private var subline: String {
    if isStale { return state.lastSyncLabel }
    let hidden = (state.isCompleted ? state.completedItems.count : state.activeCount) - items.count
    if hidden > 0 { return state.othersLabel(hidden) }
    return state.isCompleted ? state.emptyLabel : items.first?.statusLabel ?? ""
  }
}

struct IslandRow: View {
  let item: LodyItem
  let state: LodyState

  var body: some View {
    HStack(spacing: 8) {
      LeadGlyph(item: item, size: 18)
      Text(item.title)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: 4)
      if state.showsTimer(for: item, isStale: false) {
        WorkTimer(item: item)
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct OthersList: View {
  let state: LodyState
  let items: [LodyItem]
  let workspaceSlug: String
  let isStale: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(items, id: \.id) { item in
        Link(destination: LodyActivityAttributes.route(workspaceSlug: workspaceSlug, sessionId: item.id)) {
          HStack(spacing: 8) {
            LeadGlyph(item: item, size: 20)
            Text(item.title)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            Spacer(minLength: 4)
            if state.showsTimer(for: item, isStale: isStale) {
              WorkTimer(item: item)
                .foregroundStyle(.secondary)
            }
          }
          .frame(minHeight: 34)
          .contentShape(Rectangle())
        }
      }
    }
    .padding(.top, 4)
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
  let copy: LodyState

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
  let state: LodyState
  let workspaceSlug: String
  var overviewRoute: URL = URL(string: "lody:///activity")!
  let isStale: Bool

  var body: some View {
    content
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background {
        ZStack {
          LinearGradient(
            colors: [.black.opacity(0.58), .black.opacity(0.24), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          wash
          JellyGlow(opacity: isStale ? 0.15 : 0.42)
        }
        .mask {
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0),
              .init(color: .white, location: 0.2),
              .init(color: .white, location: 0.8),
              .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
        }
        .mask {
          LinearGradient(
            stops: [
              .init(color: .clear, location: 0),
              .init(color: .white, location: 0.3),
              .init(color: .white, location: 0.7),
              .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        }
        .padding(6)
      }
      .lodyStale(isStale)
  }

  @ViewBuilder
  private var content: some View {
    if let focus = state.focus {
      VStack(alignment: .leading, spacing: 10) {
        if state.showsOverview || (state.isCompleted && state.completedItems.count > 1) {
          OverviewHeader(state: state, items: state.visibleItems, isStale: isStale)
          OthersList(state: state, items: state.visibleItems, workspaceSlug: workspaceSlug, isStale: isStale)
        } else {
          Link(destination: LodyActivityAttributes.route(workspaceSlug: workspaceSlug, sessionId: focus.id)) {
            FocusRow(state: state, focus: focus, isStale: isStale, glyphSize: 36)
              .frame(minHeight: 44)
          }
          if !isStale, state.needsAttention {
            AttentionBlock(focus: focus, copy: state)
          }
        }
      }
      .widgetURL(state.showsOverview ? overviewRoute : LodyActivityAttributes.route(workspaceSlug: workspaceSlug, sessionId: focus.id))
    } else {
      Text(state.emptyLabel)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var wash: some View {
    if isStale {
      Color.clear
    } else if state.needsAttention {
      LinearGradient(colors: [Color.orange.opacity(0.2), .clear], startPoint: .topLeading, endPoint: UnitPoint(x: 0.6, y: 1))
    } else if state.isCompleted {
      LinearGradient(colors: [LodyTone.blue.opacity(0.16), LodyTone.teal.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
    } else {
      Color.clear
    }
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
