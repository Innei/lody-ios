#if DEBUG
import ActivityKit
import SwiftUI
import WidgetKit

enum LiveActivityFixtures {
  typealias State = LodyActivityAttributes.ContentState
  typealias Item = State.Item

  static let attributes = LodyActivityAttributes(
    workspaceId: "preview",
    workspaceSlug: "preview",
    workspaceName: "Preview",
    userId: "preview"
  )

  static let copy = State.Copy(
    stale: "Disconnected",
    empty: "No active sessions",
    others: "{count} more running",
    lastSync: "Last synced",
    openHint: "Tap to review"
  )

  private static let now = Date().timeIntervalSince1970 * 1000

  private static func item(
    _ id: String,
    _ status: Item.Status,
    _ title: String,
    agent: String,
    ago seconds: Double,
    command: String? = nil
  ) -> Item {
    let labels: [Item.Status: String] = [
      .running: "Working", .permission: "Needs your approval", .question: "Has a question for you", .unread: "New reply",
    ]
    let glyphs = ["claude": "CC", "codex": "CX"]
    return Item(
      id: id,
      status: status,
      statusLabel: labels[status] ?? status.rawValue,
      permissionRequestId: command == nil ? nil : "preview-request",
      permissionCommand: command,
      agentLogoKind: agent,
      agentLogoText: glyphs[agent] ?? agent.prefix(2).uppercased(),
      title: title,
      updatedAt: now - seconds * 1000,
      updatedAtLabel: ""
    )
  }

  private static func state(_ items: [Item]) -> State {
    var counts = State.Counts()
    counts.running = items.count { $0.status == .running }
    counts.permission = items.count { $0.status == .permission }
    counts.question = items.count { $0.status == .question }
    counts.unread = items.count { $0.status == .unread }
    return State(totalCount: items.count, statusCounts: counts, items: items, permissionAlert: nil, copy: copy)
  }

  static let running = state([
    item("1", .running, "Refactor session list paging", agent: "claude", ago: 761),
    item("2", .running, "Poll GitHub PR status", agent: "codex", ago: 187),
    item("3", .running, "Write the watchdog Swift check", agent: "claude", ago: 48),
  ])

  static let single = state([
    item("1", .running, "Refactor session list paging", agent: "claude", ago: 761),
  ])

  static let permission = state([
    item("1", .running, "Refactor session list paging", agent: "claude", ago: 761),
    item("2", .permission, "Poll GitHub PR status", agent: "codex", ago: 123,
         command: "pnpm exec eas build --platform ios --profile preview"),
  ])

  static let question = state([
    item("1", .question, "Migrate the Keychain access group", agent: "claude", ago: 40),
  ])

  static let unknownAgent = state([
    item("1", .running, "Generate the changelog", agent: "agent", ago: 12),
    item("2", .unread, "Fix the CI cache key", agent: "codex", ago: 200),
  ])

  static let brands = state([
    item("1", .running, "Port the parser to Kimi", agent: "kimi-code", ago: 30),
    item("2", .running, "Grok build sweep", agent: "grok", ago: 90),
  ])

  static let done = state([
    item("1", .unread, "Fix the CI cache key", agent: "codex", ago: 200),
  ])
}

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
