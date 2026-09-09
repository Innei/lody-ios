import ActivityKit
import Foundation
import OneSignalFramework
import OneSignalLiveActivities

@MainActor
final class LiveActivities {
  static let shared = LiveActivities()
  private let defaults = UserDefaults(suiteName: "group.app.innei.lody")
  private var tokenTasks: [String: Task<Void, Never>] = [:]

  var enabled: Bool {
    get { defaults?.object(forKey: "liveActivitiesEnabled") as? Bool ?? true }
    set {
      defaults?.set(newValue, forKey: "liveActivitiesEnabled")
      if !newValue { endAll(reason: "disabled") }
    }
  }

  func start() {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    if #available(iOS 17.2, *) {
      Task { @MainActor in
        for await token in Activity<LodyActivityAttributes>.pushToStartTokenUpdates {
          OneSignal.LiveActivities.setPushToStartToken(LodyActivityAttributes.self, withToken: Self.hex(token))
        }
      }
    }
    for activity in Activity<LodyActivityAttributes>.activities { observe(activity) }
  }

  func sync(catalogJSON: String, workspaceId: String, workspaceSlug: String, workspaceName: String, userId: String) {
    guard enabled, !workspaceId.isEmpty, !userId.isEmpty,
          ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let id = LodyActivityAttributes.activityId(workspaceId: workspaceId, userId: userId)
    guard !Activity<LodyActivityAttributes>.activities.contains(where: { Self.id(of: $0) == id }) else { return }
    let state = LiveActivityCatalog.state(catalogJSON: catalogJSON)
    guard state.isActive else { return }
    let attributes = LodyActivityAttributes(
      workspaceId: workspaceId,
      workspaceSlug: workspaceSlug,
      workspaceName: workspaceName,
      userId: userId
    )
    let content = ActivityContent(state: state, staleDate: state.staleDate(from: Date()))
    guard let activity = try? Activity.request(attributes: attributes, content: content, pushType: .token) else { return }
    observe(activity)
  }

  func endAll(reason: String) {
    tokenTasks.values.forEach { $0.cancel() }
    tokenTasks = [:]
    for activity in Activity<LodyActivityAttributes>.activities {
      OneSignal.LiveActivities.exit(Self.id(of: activity))
    }
    Self.endActivities()
  }

  // ActivityKit's Activity is not Sendable, so every await on one stays inside a
  // nonisolated task that fetches it itself instead of crossing off the main actor.
  private nonisolated static func endActivities(workspaceId: String? = nil) {
    Task {
      for activity in Activity<LodyActivityAttributes>.activities
      where workspaceId == nil || activity.attributes.workspaceId == workspaceId {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
  }

  func status() -> [String: any Sendable] {
    [
      "enabled": enabled,
      "supported": ActivityAuthorizationInfo().areActivitiesEnabled,
      "active": Activity<LodyActivityAttributes>.activities.count,
    ]
  }

  private func observe(_ activity: Activity<LodyActivityAttributes>) {
    let id = Self.id(of: activity)
    guard tokenTasks[id] == nil else { return }
    tokenTasks[id] = Task { @MainActor in
      for await token in activity.pushTokenUpdates {
        OneSignal.LiveActivities.enter(id, withToken: Self.hex(token))
      }
      tokenTasks[id] = nil
    }
  }

  private static func id(of activity: Activity<LodyActivityAttributes>) -> String {
    LodyActivityAttributes.activityId(
      workspaceId: activity.attributes.workspaceId,
      userId: activity.attributes.userId
    )
  }

  private static func hex(_ token: Data) -> String {
    token.map { String(format: "%02x", $0) }.joined()
  }

  #if DEBUG
  private static let debugAttributes = LodyActivityAttributes(
    workspaceId: "debug",
    workspaceSlug: "debug",
    workspaceName: "Debug",
    userId: "debug"
  )

  func debug(_ action: String) {
    let existing = Activity<LodyActivityAttributes>.activities.filter { $0.attributes.workspaceId == "debug" }
    switch action {
    case "start-running":
      guard existing.isEmpty, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
      let content = ActivityContent(state: Self.debugState(), staleDate: nil)
      _ = try? Activity.request(attributes: Self.debugAttributes, content: content, pushType: nil)
    case "update-permission":
      Self.updateDebugActivities()
    case "end":
      Self.endActivities(workspaceId: "debug")
    default: break
    }
  }

  private nonisolated static func updateDebugActivities() {
    let state = debugState(permission: true)
    let alert = AlertConfiguration(
      title: "需要你授权",
      body: "git push origin main --force",
      sound: .default
    )
    Task {
      for activity in Activity<LodyActivityAttributes>.activities where activity.attributes.workspaceId == "debug" {
        await activity.update(ActivityContent(state: state, staleDate: nil), alertConfiguration: alert)
      }
    }
  }

  private nonisolated static func debugItem(
    _ id: String,
    _ status: LodyActivityAttributes.ContentState.Item.Status,
    _ title: String,
    _ agent: String,
    _ updatedAt: Double,
    command: String? = nil
  ) -> LodyActivityAttributes.ContentState.Item {
    let labels: [LodyActivityAttributes.ContentState.Item.Status: String] = [
      .permission: "需要你授权", .running: "正在工作", .unread: "有新回复", .question: "有问题要问你",
    ]
    return LodyActivityAttributes.ContentState.Item(
      id: id,
      status: status,
      statusLabel: labels[status] ?? "",
      permissionRequestId: command == nil ? nil : "debug-request",
      permissionCommand: command,
      agentLogoKind: agent == "CC" ? "claude" : "codex",
      agentLogoText: agent,
      title: title,
      updatedAt: updatedAt,
      updatedAtLabel: "刚刚"
    )
  }

  private nonisolated static func debugState(permission: Bool = false) -> LodyActivityAttributes.ContentState {
    let now = Date().timeIntervalSince1970 * 1000
    let second = debugItem(
      "debug-2",
      permission ? .permission : .running,
      "修复 push-extension 签名",
      "CX",
      now - 1000,
      command: permission ? "git push origin main --force" : nil
    )
    return LodyActivityAttributes.ContentState(
      totalCount: 3,
      statusCounts: .init(permission: permission ? 1 : 0, running: permission ? 1 : 2, unread: 1),
      items: [
        debugItem("debug-1", .running, "重构 composer 键盘避让", "CC", now),
        second,
        debugItem("debug-3", .unread, "写 Live Activity 设计文档", "CC", now - 2000),
      ],
      permissionAlert: permission
        ? .init(title: "需要你授权", body: "git push origin main --force")
        : nil
    )
  }
  #endif
}
