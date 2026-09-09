import ActivityKit
import Foundation
import os
import OneSignalFramework
import OneSignalLiveActivities

@MainActor
final class LiveActivities {
  static let shared = LiveActivities()
  private let defaults = UserDefaults(suiteName: "group.app.innei.lody")
  private var tokenTasks: [String: (stamp: UUID, task: Task<Void, Never>)] = [:]
  private var pushToStartTask: Task<Void, Never>?
  private var activityTask: Task<Void, Never>?

  var enabled: Bool {
    get { defaults?.object(forKey: "liveActivitiesEnabled") as? Bool ?? true }
    set {
      defaults?.set(newValue, forKey: "liveActivitiesEnabled")
      if newValue {
        registerPushToStart()
        return
      }
      endAll()
      pushToStartTask?.cancel()
      pushToStartTask = nil
      if #available(iOS 17.2, *) {
        OneSignal.LiveActivities.removePushToStartToken(LodyActivityAttributes.self)
      }
    }
  }

  func start() {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    registerPushToStart()
    for activity in Activity<LodyActivityAttributes>.activities { observe(activity) }
    guard activityTask == nil else { return }
    activityTask = Task { @MainActor in
      for await activity in Activity<LodyActivityAttributes>.activityUpdates { observe(activity) }
    }
  }

  private func registerPushToStart() {
    guard enabled, pushToStartTask == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    guard #available(iOS 17.2, *) else { return }
    pushToStartTask = Task { @MainActor in
      for await token in Activity<LodyActivityAttributes>.pushToStartTokenUpdates {
        OneSignal.LiveActivities.setPushToStartToken(LodyActivityAttributes.self, withToken: Self.hex(token))
      }
    }
  }

  func sync(catalogJSON: String, workspaceId: String, workspaceSlug: String, workspaceName: String, userId: String) {
    guard enabled, !workspaceId.isEmpty, !userId.isEmpty,
          ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    let id = LodyActivityAttributes.activityId(workspaceId: workspaceId, userId: userId)
    endStale(keeping: id)
    guard !Activity<LodyActivityAttributes>.activities.contains(where: { Self.id(of: $0) == id }) else { return }
    guard Self.mayBeActive(catalogJSON) else { return }
    let state = LiveActivityCatalog.state(catalogJSON: catalogJSON, labels: Self.labels)
    guard state.isActive else { return }
    let attributes = LodyActivityAttributes(
      workspaceId: workspaceId,
      workspaceSlug: workspaceSlug,
      workspaceName: workspaceName,
      userId: userId
    )
    let content = ActivityContent(state: state, staleDate: state.staleDate(from: Date()))
    do {
      observe(try Activity.request(attributes: attributes, content: content, pushType: .token))
    } catch {
      Self.log.error("activity request failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private nonisolated static let log = Logger(subsystem: "app.innei.lody", category: "live-activity")

  private nonisolated static let activeTokens = ["awaitingUserSince"] + Array(LiveActivityCatalog.runningStatuses)

  private nonisolated static func mayBeActive(_ catalogJSON: String) -> Bool {
    activeTokens.contains { catalogJSON.contains($0) }
  }

  func endAll() {
    tokenTasks.values.forEach { $0.task.cancel() }
    tokenTasks = [:]
    for activity in Activity<LodyActivityAttributes>.activities where !Self.isDebug(activity.attributes) {
      OneSignal.LiveActivities.exit(Self.id(of: activity))
    }
    Self.endActivities()
  }

  private func endStale(keeping id: String) {
    var stale = false
    for activity in Activity<LodyActivityAttributes>.activities where !Self.isDebug(activity.attributes) {
      let other = Self.id(of: activity)
      guard other != id else { continue }
      stale = true
      OneSignal.LiveActivities.exit(other)
      tokenTasks.removeValue(forKey: other)?.task.cancel()
    }
    guard stale else { return }
    Self.endActivities { !Self.isDebug($0) && Self.activityId(of: $0) != id }
  }

  // ActivityKit's Activity is not Sendable, so every await on one stays inside a
  // nonisolated task that fetches it itself instead of crossing off the main actor.
  private nonisolated static func endActivities(
    where matches: @escaping @Sendable (LodyActivityAttributes) -> Bool = { _ in true }
  ) {
    Task {
      for activity in Activity<LodyActivityAttributes>.activities where matches(activity.attributes) {
        await activity.end(nil, dismissalPolicy: .immediate)
      }
    }
  }

  private nonisolated static func isDebug(_ attributes: LodyActivityAttributes) -> Bool {
    attributes.workspaceId == "debug"
  }

  private nonisolated static func activityId(of attributes: LodyActivityAttributes) -> String {
    LodyActivityAttributes.activityId(workspaceId: attributes.workspaceId, userId: attributes.userId)
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
    guard tokenTasks[id] == nil, !Self.isDebug(activity.attributes) else { return }
    let stamp = UUID()
    tokenTasks[id] = (stamp, Task { @MainActor in
      for await token in activity.pushTokenUpdates {
        OneSignal.LiveActivities.enter(id, withToken: Self.hex(token))
      }
      if tokenTasks[id]?.stamp == stamp { tokenTasks[id] = nil }
    })
  }

  private static func id(of activity: Activity<LodyActivityAttributes>) -> String {
    LodyActivityAttributes.activityId(
      workspaceId: activity.attributes.workspaceId,
      userId: activity.attributes.userId
    )
  }

  private nonisolated static var labels: LiveActivityCatalog.Labels {
    .init(
      permission: LodyStrings.text("native.liveActivity.status.permission"),
      running: LodyStrings.text("native.liveActivity.status.running"),
      stale: LodyStrings.text("native.liveActivity.stale"),
      empty: LodyStrings.text("native.liveActivity.empty"),
      others: LodyStrings.text("native.liveActivity.others")
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
      Self.endActivities(where: Self.isDebug)
    default: break
    }
  }

  private nonisolated static func updateDebugActivities() {
    let state = debugState(permission: true)
    let alert = AlertConfiguration(
      title: LocalizedStringResource(stringLiteral: LodyStrings.text("native.liveActivity.debug.alertTitle")),
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
    return LodyActivityAttributes.ContentState.Item(
      id: id,
      status: status,
      statusLabel: LodyStrings.text("native.liveActivity.status.\(status.rawValue)"),
      permissionRequestId: command == nil ? nil : "debug-request",
      permissionCommand: command,
      agentLogoKind: agent == "CC" ? "claude" : "codex",
      agentLogoText: agent,
      title: title,
      updatedAt: updatedAt,
      updatedAtLabel: LodyStrings.text("native.liveActivity.debug.updatedAt")
    )
  }

  private nonisolated static func debugState(permission: Bool = false) -> LodyActivityAttributes.ContentState {
    let now = Date().timeIntervalSince1970 * 1000
    let second = debugItem(
      "debug-2",
      permission ? .permission : .running,
      LodyStrings.text("native.liveActivity.debug.title2"),
      "CX",
      now - 1000,
      command: permission ? "git push origin main --force" : nil
    )
    return LodyActivityAttributes.ContentState(
      totalCount: 3,
      statusCounts: .init(permission: permission ? 1 : 0, running: permission ? 1 : 2, unread: 1),
      items: [
        debugItem("debug-1", .running, LodyStrings.text("native.liveActivity.debug.title1"), "CC", now),
        second,
        debugItem("debug-3", .unread, LodyStrings.text("native.liveActivity.debug.title3"), "CC", now - 2000),
      ],
      permissionAlert: permission
        ? .init(title: LodyStrings.text("native.liveActivity.debug.alertTitle"), body: "git push origin main --force")
        : nil,
      copy: .init(stale: labels.stale, empty: labels.empty, others: labels.others)
    )
  }
  #endif
}
