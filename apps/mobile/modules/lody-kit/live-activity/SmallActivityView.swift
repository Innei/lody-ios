import CoreText
import SwiftUI
import WidgetKit

// The small family is shared by Smart Stack and CarPlay. Measure the container,
// not the device model; the system owns the platter, clipping and tap behaviour.
struct LodySmallActivityView: View {
  @Environment(\.isLuminanceReduced) private var isLuminanceReduced
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let state: LodyState
  let isStale: Bool

  var body: some View {
    GeometryReader { geometry in
      let metrics = SmallActivityMetrics(width: geometry.size.width)
      SmallActivitySpacing(titleSize: isOverview ? nil : metrics.title) {
        header(metrics)
        if isOverview {
          overview(metrics)
        } else if let focus = state.focus {
          Text(focus.title)
            .font(.system(size: metrics.title, weight: .semibold))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Text(state.emptyLabel)
            .font(.system(size: metrics.title, weight: .semibold))
            .lineLimit(2)
        }
      }
      .padding(.horizontal, metrics.inset)
      .background(alignment: .bottomTrailing) {
        if !isLuminanceReduced {
          ZStack(alignment: .bottomTrailing) {
            wash
            SmallActivityGlow(opacity: isStale ? 0.11 : 0.30)
              .offset(x: 22, y: 26)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
      }
      .clipped()
      .lodyStale(isStale)
    }
  }

  private var isOverview: Bool {
    state.showsOverview || (state.isCompleted && state.completedItems.count > 1)
  }

  private var status: LodyItem.Status {
    if state.allFailed { return .failed }
    if state.isCompleted { return .unread }
    return state.focus?.status ?? .running
  }

  private var statusColor: Color {
    if isStale { return .secondary }
    switch status {
    case .running: return .secondary
    case .permission, .question: return .orange
    case .unread: return .blue
    case .failed: return .red
    }
  }

  private var label: String {
    if isStale { return state.smallStale }
    if isOverview {
      if state.isCompleted {
        if state.allFailed { return "\(state.completedItems.count) \(state.smallFailed)" }
        return state.completedSummary(state.completedItems.count)
      }
      return state.runningSummary
    }
    if state.needsAttention { return state.smallAttention }
    return state.focus?.statusLabel ?? state.emptyLabel
  }

  private var shortLabel: String {
    if isStale || isOverview { return label }
    if state.needsAttention { return state.smallWaiting }
    if status == .unread { return state.smallDone }
    return label
  }

  private func header(_ metrics: SmallActivityMetrics) -> some View {
    HStack(spacing: metrics.gap) {
      glyph(item: isOverview ? nil : state.focus, size: metrics.icon, dot: metrics.dot)
      ViewThatFits(in: .horizontal) {
        Text(label).fixedSize()
        Text(shortLabel).fixedSize()
        Text(shortLabel).lineLimit(1)
      }
      .font(.system(size: metrics.label, weight: .semibold))
      .foregroundStyle(statusColor.opacity(isLuminanceReduced ? 0.65 : 1))
      .frame(maxWidth: .infinity, alignment: .leading)
      if isStale, let focus = state.focus {
        HStack(spacing: 2) {
          Image(systemName: "clock.badge.exclamationmark")
          Text(.dateRange(startingAt: focus.updatedDate), format: .components(style: .narrow, fields: [.minute]))
        }
        .font(.system(size: metrics.label - 1))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: 45)
        .accessibilityLabel(Text("\(state.lastSyncLabel) \(Text(focus.updatedDate, style: .relative))"))
      } else if isOverview {
        let hidden = max(0, overviewCount - state.visibleItems.count)
        if hidden > 0 {
          Text("+\(hidden)")
            .font(.system(size: metrics.label - 2, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.primary.opacity(0.16), in: Capsule())
        }
      } else if let focus = state.focus, state.showsTimer(for: focus, isStale: false) {
        SmallActivityTimer(item: focus, size: metrics.title, reduced: isLuminanceReduced)
      }
    }
    .frame(height: metrics.icon)
  }

  private var overviewCount: Int {
    state.isCompleted ? state.completedItems.count : state.activeCount
  }

  private func overview(_ metrics: SmallActivityMetrics) -> some View {
    VStack(spacing: metrics.rowGap) {
      ForEach(state.visibleItems, id: \.id) { item in
        HStack(spacing: 5) {
          AgentGlyph(kind: item.agentLogoKind, text: item.agentLogoText, size: metrics.rowIcon, reducedLuminance: isLuminanceReduced)
          Text(item.title)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
          if state.showsTimer(for: item, isStale: isStale) {
            SmallActivityTimer(item: item, size: metrics.rowText, reduced: isLuminanceReduced)
          }
        }
        .font(.system(size: metrics.rowText, weight: .medium))
      }
    }
  }

  private func glyph(item: LodyItem?, size: CGFloat, dot: CGFloat) -> some View {
    let ring = dot + (size < 19 ? 4.5 : 5)
    return Group {
      if let item {
        AgentGlyph(kind: item.agentLogoKind, text: item.agentLogoText, size: size, reducedLuminance: isLuminanceReduced)
      } else {
        JellyMark().scaleEffect(size / JellyMark.pointSize).frame(width: size, height: size)
      }
    }
    .overlay(alignment: .bottomTrailing) {
      Image(systemName: "circle.fill")
        .resizable()
        .foregroundStyle(dotGradient)
        .opacity(isLuminanceReduced ? 0.55 : 1)
        .frame(width: dot, height: dot)
        .padding((ring - dot) / 2)
        .background(isLuminanceReduced ? Color.black : Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255), in: Circle())
        .offset(x: ring / 3, y: ring / 3)
        .symbolEffect(.pulse, isActive: status == .running && !isStale && !isLuminanceReduced && !reduceMotion)
        .accessibilityHidden(true)
    }
    .accessibilityHidden(true)
  }

  private var dotGradient: LinearGradient {
    let colors: [Color]
    if isStale {
      colors = [.secondary, .secondary]
    } else {
      switch status {
      case .running: colors = [LodyTone.blue, LodyTone.teal]
      case .permission, .question: colors = [.orange, .yellow]
      case .unread: colors = [.blue, .cyan]
      case .failed: colors = [.red, .pink]
      }
    }
    return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  @ViewBuilder private var wash: some View {
    if !isStale {
      switch status {
      case .permission, .question:
        LinearGradient(colors: [.orange.opacity(0.20), .clear], startPoint: .topLeading, endPoint: UnitPoint(x: 0.6, y: 1))
      case .unread:
        LinearGradient(colors: [LodyTone.blue.opacity(0.16), LodyTone.teal.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
      case .failed:
        GeometryReader { geometry in
          // CSS 135deg runs at 45 degrees in point space, independent of the
          // card's aspect ratio; its transparent stop is at 60% of that line.
          let length = (geometry.size.width + geometry.size.height) / 2
          let start = CGPoint(x: (geometry.size.width - length) / 2, y: (geometry.size.height - length) / 2)
          LinearGradient(
            stops: [.init(color: .red.opacity(0.18), location: 0), .init(color: .clear, location: 0.6)],
            startPoint: UnitPoint(x: start.x / geometry.size.width, y: start.y / geometry.size.height),
            endPoint: UnitPoint(x: (start.x + length) / geometry.size.width, y: (start.y + length) / geometry.size.height)
          )
        }
      case .running: Color.clear
      }
    }
  }
}

private struct SmallActivityMetrics {
  let width: CGFloat
  private var small: Bool { width < 170 }
  private var medium: Bool { width >= 170 && width < 180 }
  private func value(_ large: CGFloat, _ middle: CGFloat, _ compact: CGFloat) -> CGFloat {
    if small { return compact }
    if medium { return middle }
    return large
  }
  var icon: CGFloat { value(20, 19, 17) }
  var dot: CGFloat { value(7, 6.5, 6) }
  var title: CGFloat { value(15, 14.5, 13.5) }
  var label: CGFloat { value(13, 12.5, 12) }
  var rowText: CGFloat { value(13, 12.5, 12) }
  var rowIcon: CGFloat { value(14, 13.5, 12.5) }
  var inset: CGFloat { small ? 8 : 9.5 }
  var gap: CGFloat { small ? 5 : 6 }
  var rowGap: CGFloat { small ? 4 : 5 }
}

// Text is measured at its natural one/two-line height. Equal free space above,
// between and below the two blocks keeps short titles centred without spacers
// compressing the title before SwiftUI has measured its second line.
private struct SmallActivitySpacing: Layout {
  let titleSize: CGFloat?
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let measured = subviews.map { $0.dimensions(in: ProposedViewSize(width: bounds.width, height: nil)) }
    var topTrim: CGFloat = 0
    var bottomTrim: CGFloat = 0
    if let titleSize, measured.count > 1,
       let font = CTFontCreateUIFontForLanguage(.system, titleSize, nil) {
      let title = measured[1]
      topTrim = max(0, title[.firstTextBaseline] - CTFontGetCapHeight(font))
      bottomTrim = max(0, title.height - title[.lastTextBaseline])
    }
    let inkHeight = measured.reduce(0) { $0 + $1.height } - topTrim - bottomTrim
    let gap = max(0, (bounds.height - inkHeight) / CGFloat(measured.count + 1))
    var y = bounds.minY + gap
    for (index, subview) in subviews.enumerated() {
      if index == 1 { y -= topTrim }
      subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: measured[index].height))
      y += measured[index].height + gap
    }
  }
}

private struct SmallActivityTimer: View {
  let item: LodyItem
  let size: CGFloat
  let reduced: Bool

  var body: some View {
    Group {
      if reduced {
        let format = Date.ComponentsFormatStyle(style: .abbreviated, fields: [.minute])
        if let end = item.completedDate {
          Text(item.startDate..<max(end, item.startDate), format: format)
        } else {
          Text(.dateRange(startingAt: item.startDate), format: format)
        }
      } else {
        WorkTimer(item: item, font: .system(size: size, weight: .semibold, design: .rounded).monospacedDigit(), width: size * 2.7)
      }
    }
    .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .frame(width: size * (reduced ? 3.1 : 2.7), alignment: .trailing)
    .foregroundStyle(reduced ? .secondary : .primary)
  }
}

private struct SmallActivityGlow: View {
  @AppStorage(LodyActivityIcon.key, store: LodyActivityIcon.defaults) private var appIcon = "default"
  let opacity: Double

  var body: some View {
    Image(LodyActivityIcon.asset(name: appIcon, mark: false) + "-small")
      .resizable()
      .frame(width: 84, height: 84)
      // CSS radial-gradient uses the farthest corner as its 100% radius.
      .mask(RadialGradient(
        stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.45), location: 0.34), .init(color: .clear, location: 0.5)],
        center: UnitPoint(x: 0.45, y: 0.4), startRadius: 0,
        endRadius: hypot(84 * 0.55, 84 * 0.6)
      ))
      .opacity(opacity)
      .accessibilityHidden(true)
  }
}
