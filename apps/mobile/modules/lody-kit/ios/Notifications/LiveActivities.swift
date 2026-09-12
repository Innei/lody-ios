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
  private var syncTask: Task<Void, Never>?

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
      OneSignal.LiveActivities.removePushToStartToken(LodyActivityAttributes.self)
    }
  }

  func start() {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    registerPushToStart()
    observeCurrentActivities()
    guard activityTask == nil else { return }
    activityTask = Task { @MainActor in
      for await activity in Activity<LodyActivityAttributes>.activityUpdates { observe(activity) }
    }
  }

  private func registerPushToStart() {
    guard enabled, pushToStartTask == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
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
    guard let root = try? JSONSerialization.jsonObject(with: Data(catalogJSON.utf8)) as? [String: Any],
          let sessions = root["sessions"] as? [[String: Any]] else { return }
    let state = LiveActivityCatalog.state(sessions: sessions, labels: Self.labels)
    let attributes = LodyActivityAttributes(
      workspaceId: workspaceId,
      workspaceSlug: workspaceSlug,
      workspaceName: workspaceName,
      userId: userId
    )
    let previous = syncTask
    previous?.cancel()
    syncTask = Task {
      await previous?.value
      guard !Task.isCancelled else { return }
      await Self.reconcile(attributes: attributes, state: state)
    }
  }

  private nonisolated static func reconcile(
    attributes: LodyActivityAttributes,
    state: LodyActivityAttributes.ContentState
  ) async {
    let id = activityId(of: attributes)
    let existing = Activity<LodyActivityAttributes>.activities.filter {
      activityId(of: $0.attributes) == id && ($0.activityState == .active || $0.activityState == .stale)
    }
    let now = Date()
    var summary = state
    summary.items = state.visibleItems
    summary.totalCount = state.activeCount
    summary.statusCounts.unread = 0
    let content = ActivityContent(state: summary, staleDate: state.staleDate(from: now))
    for activity in existing {
      guard !Task.isCancelled else { return }
      if state.isActive {
        await activity.update(content)
      } else {
        if !isDebug(attributes) { await shared.unregister(id) }
        await activity.end(content, dismissalPolicy: .after(state.dismissalDate(from: now) ?? now))
      }
    }
    guard !Task.isCancelled, existing.isEmpty, state.isActive else { return }
    for activity in Activity<LodyActivityAttributes>.activities where activityId(of: activity.attributes) == id && activity.activityState == .ended {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    guard !Task.isCancelled else { return }
    do {
      _ = try Activity.request(attributes: attributes, content: content, pushType: isDebug(attributes) ? nil : .token)
      if !Task.isCancelled { await shared.observeCurrentActivities() }
    } catch {
      log.error("activity request failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private nonisolated static let log = Logger(subsystem: "app.innei.lody", category: "live-activity")

  private func unregister(_ id: String) {
    tokenTasks.removeValue(forKey: id)?.task.cancel()
    OneSignal.LiveActivities.exit(id)
  }

  func endAll() {
    syncTask?.cancel()
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
      "active": Activity<LodyActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }.count,
    ]
  }

  private func observe(_ activity: Activity<LodyActivityAttributes>) {
    let id = Self.id(of: activity)
    guard enabled, tokenTasks[id] == nil, !Self.isDebug(activity.attributes),
          activity.activityState == .active || activity.activityState == .stale else { return }
    let stamp = UUID()
    tokenTasks[id] = (stamp, Task { @MainActor in
      for await token in activity.pushTokenUpdates {
        OneSignal.LiveActivities.enter(id, withToken: Self.hex(token))
      }
      if tokenTasks[id]?.stamp == stamp { tokenTasks[id] = nil }
    })
  }

  private func observeCurrentActivities() {
    guard !Task.isCancelled else { return }
    for activity in Activity<LodyActivityAttributes>.activities { observe(activity) }
  }

  private static func id(of activity: Activity<LodyActivityAttributes>) -> String {
    LodyActivityAttributes.activityId(
      workspaceId: activity.attributes.workspaceId,
      userId: activity.attributes.userId
    )
  }

  private nonisolated static var labels: LiveActivityCatalog.Labels {
    .init(
      permission: LodyStrings.text("native.liveActivity.status.attention"),
      running: LodyStrings.text("native.liveActivity.status.running"),
      stale: LodyStrings.text("native.liveActivity.stale"),
      empty: LodyStrings.text("native.liveActivity.empty"),
      others: LodyStrings.text("native.liveActivity.others"),
      lastSync: LodyStrings.text("native.liveActivity.lastSync"),
      openHint: LodyStrings.text("native.liveActivity.openHint"),
      runningSummary: LodyStrings.text("native.liveActivity.runningSummary")
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
    switch action {
    case "start-running":
      Task { await Self.reconcile(attributes: Self.debugAttributes, state: Self.debugState()) }
    case "complete-one", "complete-all":
      var state = Self.debugState()
      state.items = action == "complete-one" ? Array(state.items.filter { $0.status == .running }.dropFirst()) : []
      state.totalCount = state.items.count
      state.statusCounts = .init(running: state.items.count)
      Task { await Self.reconcile(attributes: Self.debugAttributes, state: state) }
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
      totalCount: 2,
      statusCounts: .init(permission: permission ? 1 : 0, running: permission ? 1 : 2),
      items: [
        debugItem("debug-1", .running, LodyStrings.text("native.liveActivity.debug.title1"), "CC", now),
        second,
      ],
      permissionAlert: permission
        ? .init(title: LodyStrings.text("native.liveActivity.debug.alertTitle"), body: "git push origin main --force")
        : nil,
      copy: debugCopy
    )
  }

  private nonisolated static var debugCopy: LodyActivityAttributes.ContentState.Copy {
    var copy = LodyActivityAttributes.ContentState.Copy(stale: labels.stale, empty: labels.empty, others: labels.others, lastSync: labels.lastSync, openHint: labels.openHint)
    copy.runningSummary = labels.runningSummary
    return copy
  }
  #endif
}
