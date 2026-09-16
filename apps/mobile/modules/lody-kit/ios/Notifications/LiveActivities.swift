import ActivityKit
import Foundation
import os
import OneSignalFramework
import OneSignalLiveActivities

@MainActor
final class LiveActivities {
  static let shared = LiveActivities()
  private let defaults = UserDefaults(suiteName: "group.app.innei.lody")
  private var tokenTasks: [String: (stamp: UUID, nativeId: String, task: Task<Void, Never>, lifecycle: Task<Void, Never>)] = [:]
  private var pushToStartTask: Task<Void, Never>?
  private var activityTask: Task<Void, Never>?
  private var syncTask: Task<Void, Never>?
  private var workStarts: [String: Double] = [:]
  private var userId: String?
  private var identityResolved = false

  var enabled: Bool {
    get { defaults?.object(forKey: "liveActivitiesEnabled") as? Bool ?? true }
    set {
      defaults?.set(newValue, forKey: "liveActivitiesEnabled")
      if newValue {
        start()
        return
      }
      endAll()
      removePushToStart()
    }
  }

  func start() {
    // Offline Debug scenes must never initialize/register with OneSignal.
    guard PushNotifications.shared.configured else { return }
    if !identityResolved {
      userId = OneSignal.User.externalId
      identityResolved = userId != nil
    }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    registerPushToStart()
    observeCurrentActivities()
    guard activityTask == nil else { return }
    activityTask = Task { @MainActor in
      for await activity in Activity<LodyActivityAttributes>.activityUpdates { observe(activity) }
    }
  }

  // Called before OneSignal switches identity so old bindings are detached first.
  func identify(_ id: String?) {
    // On a push-to-start cold launch, SDK identity restoration can trail ActivityKit.
    // Preserve a matching server-started activity until app auth resolves its owner.
    if !identityResolved {
      identityResolved = true
      userId = id
      if id == nil {
        removePushToStart()
        endAll()
      }
      return
    }
    guard userId != id || id == nil else { return }
    removePushToStart()
    endAll()
    userId = id
  }

  private func removePushToStart() {
    pushToStartTask?.cancel()
    pushToStartTask = nil
    guard PushNotifications.shared.configured else { return }
    OneSignal.LiveActivities.removePushToStartToken(LodyActivityAttributes.self)
  }

  private func registerPushToStart() {
    guard PushNotifications.shared.configured, let owner = userId, !owner.isEmpty,
          enabled, pushToStartTask == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    pushToStartTask = Task { @MainActor in
      guard !Task.isCancelled, enabled, userId == owner else { return }
      if let token = Activity<LodyActivityAttributes>.pushToStartToken {
        OneSignal.LiveActivities.setPushToStartToken(LodyActivityAttributes.self, withToken: Self.hex(token))
      }
      for await token in Activity<LodyActivityAttributes>.pushToStartTokenUpdates {
        guard !Task.isCancelled, enabled, userId == owner else { return }
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
    var state = LiveActivityCatalog.state(sessions: sessions, labels: Self.labels)
    let failed = LiveActivityCatalog.failedSessionIds(sessions: sessions)
    pinWorkStarts(&state)
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
      await Self.reconcile(attributes: attributes, state: state, failed: failed)
    }
  }

  // A permission pause re-stamps lastRunningSeen when the agent resumes, so the
  // earliest start seen while a session stays active is the one the turn keeps.
  private func pinWorkStarts(_ state: inout LodyActivityAttributes.ContentState) {
    var kept: [String: Double] = [:]
    for index in state.items.indices {
      let item = state.items[index]
      guard !item.isDone, let started = item.startedAt else { continue }
      let pinned = min(started, workStarts[item.id] ?? started)
      kept[item.id] = pinned
      state.items[index].startedAt = pinned
    }
    workStarts = kept
  }

  private nonisolated static func reconcile(
    attributes: LodyActivityAttributes,
    state: LodyActivityAttributes.ContentState,
    failed: Set<String> = []
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
        let ended = completed(summary, previous: activity.content.state, failed: failed, at: now)
        await activity.end(ActivityContent(state: ended, staleDate: nil), dismissalPolicy: .after(state.dismissalDate(from: now) ?? now))
      }
    }
    guard !Task.isCancelled, existing.isEmpty, state.isActive else { return }
    for activity in Activity<LodyActivityAttributes>.activities where activityId(of: activity.attributes) == id && activity.activityState == .ended {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    guard !Task.isCancelled else { return }
    do {
      let activity = try Activity.request(attributes: attributes, content: content, pushType: isDebug(attributes) ? nil : .token)
      if Task.isCancelled {
        await activity.end(nil, dismissalPolicy: .immediate)
      } else {
        await shared.observeCurrentActivities()
      }
    } catch {
      log.error("activity request failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private nonisolated static func completed(
    _ summary: LodyActivityAttributes.ContentState,
    previous: LodyActivityAttributes.ContentState,
    failed: Set<String>,
    at now: Date
  ) -> LodyActivityAttributes.ContentState {
    let stamp = now.timeIntervalSince1970 * 1000
    var ended = summary
    ended.items = previous.items.filter { !$0.isDone }.map { item in
      var done = item
      let didFail = failed.contains(item.id)
      done.status = didFail ? .failed : .unread
      done.statusLabel = (didFail ? summary.copy?.failedLabel : summary.copy?.completedLabel) ?? item.statusLabel
      done.permissionCommand = nil
      done.completedAt = stamp
      done.updatedAt = stamp
      return done
    }
    ended.statusCounts = .init(unread: ended.items.count)
    ended.totalCount = ended.items.count
    return ended
  }

  private nonisolated static let log = Logger(subsystem: "app.innei.lody", category: "live-activity")

  private func unregister(_ id: String) {
    if let observation = tokenTasks.removeValue(forKey: id) {
      observation.task.cancel()
      observation.lifecycle.cancel()
    }
    OneSignal.LiveActivities.exit(id)
  }

  func endAll() {
    syncTask?.cancel()
    let ids = Set(tokenTasks.keys).union(Activity<LodyActivityAttributes>.activities
      .filter { !Self.isDebug($0.attributes) }.map { Self.id(of: $0) })
    tokenTasks.values.forEach {
      $0.task.cancel()
      $0.lifecycle.cancel()
    }
    tokenTasks = [:]
    for id in ids { OneSignal.LiveActivities.exit(id) }
    Self.endActivities()
    workStarts = [:]
  }

  private func endStale(keeping id: String) {
    var stale = false
    for activity in Activity<LodyActivityAttributes>.activities where !Self.isDebug(activity.attributes) {
      let other = Self.id(of: activity)
      guard other != id else { continue }
      stale = true
      unregister(other)
    }
    guard stale else { return }
    Self.endActivities { !Self.isDebug($0) && Self.activityId(of: $0) != id }
  }

  // ActivityKit's Activity is not Sendable, so every await on one stays inside a
  // nonisolated task that fetches it itself instead of crossing off the main actor.
  private nonisolated static func endActivities(
    where matches: @escaping @Sendable (LodyActivityAttributes) -> Bool = { _ in true }
  ) {
    let ids = Set(Activity<LodyActivityAttributes>.activities.filter { matches($0.attributes) }.map(\.id))
    Task {
      for activity in Activity<LodyActivityAttributes>.activities where ids.contains(activity.id) {
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
    guard !Self.isDebug(activity.attributes) else { return }
    guard identityResolved || !enabled else { return }
    guard enabled, let owner = userId, activity.attributes.userId == owner else {
      let nativeId = activity.id
      Task.detached {
        for rejected in Activity<LodyActivityAttributes>.activities where rejected.id == nativeId {
          await rejected.end(nil, dismissalPolicy: .immediate)
        }
      }
      return
    }
    guard PushNotifications.shared.configured,
          activity.activityState == .active || activity.activityState == .stale else { return }
    if let current = tokenTasks[id] {
      guard current.nativeId != activity.id else { return }
      unregister(id)
    }
    let stamp = UUID()
    let tokens = Task { @MainActor in
      guard !Task.isCancelled, enabled, userId == owner else { return }
      if let token = activity.pushToken {
        OneSignal.LiveActivities.enter(id, withToken: Self.hex(token))
      }
      for await token in activity.pushTokenUpdates {
        guard !Task.isCancelled, enabled, userId == owner else { return }
        OneSignal.LiveActivities.enter(id, withToken: Self.hex(token))
      }
    }
    let lifecycle = Task { @MainActor in
      for await state in activity.activityStateUpdates {
        guard !Task.isCancelled, tokenTasks[id]?.stamp == stamp else { return }
        if state == .ended || state == .dismissed {
          unregister(id)
          return
        }
      }
    }
    tokenTasks[id] = (stamp, activity.id, tokens, lifecycle)
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
      runningSummary: LodyStrings.text("native.liveActivity.runningSummary"),
      completedSummary: LodyStrings.text("native.liveActivity.completedSummary"),
      completed: LodyStrings.text("native.liveActivity.status.unread"),
      failed: LodyStrings.text("native.liveActivity.status.failed"),
      failedSummary: LodyStrings.text("native.liveActivity.failedSummary"),
      elapsed: LodyStrings.text("native.liveActivity.caption.elapsed"),
      waiting: LodyStrings.text("native.liveActivity.caption.waiting"),
      took: LodyStrings.text("native.liveActivity.caption.took")
    )
  }

  private static func hex(_ token: Data) -> String {
    token.map { String(format: "%02x", $0) }.joined()
  }

  // Exercise the actual Convex start schema in the offline Widget fixture too.
  private static let debugAttributes = try! JSONDecoder().decode(LodyActivityAttributes.self, from: Data(#"{"activityId":"lody-conversations:v5:debug:debug","workspaceId":"debug","workspaceName":"Debug"}"#.utf8))

  func debug(_ action: String) {
    switch action {
    case "start-running":
      Task { await Self.reconcile(attributes: Self.debugAttributes, state: Self.debugState()) }
    case "complete-one", "complete-all", "fail-all":
      var state = Self.debugState()
      let failed: Set<String> = action == "fail-all" ? Set(state.items.map(\.id)) : []
      state.items = action == "complete-one" ? Array(state.items.filter { $0.status == .running }.dropFirst()) : []
      state.totalCount = state.items.count
      state.statusCounts = .init(running: state.items.count)
      Task { await Self.reconcile(attributes: Self.debugAttributes, state: state, failed: failed) }
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
    startedAgo: Double,
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
      updatedAtLabel: LodyStrings.text("native.liveActivity.debug.updatedAt"),
      startedAt: updatedAt - startedAgo * 1000
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
      startedAgo: 187,
      command: permission ? "git push origin main --force" : nil
    )
    return LodyActivityAttributes.ContentState(
      totalCount: 2,
      statusCounts: .init(permission: permission ? 1 : 0, running: permission ? 1 : 2),
      items: [
        debugItem("debug-1", .running, LodyStrings.text("native.liveActivity.debug.title1"), "CC", now, startedAgo: 761),
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
    copy.completedSummary = labels.completedSummary
    copy.completedLabel = labels.completed
    copy.failedLabel = labels.failed
    copy.failedSummary = labels.failedSummary
    copy.elapsed = labels.elapsed
    copy.waiting = labels.waiting
    copy.took = labels.took
    return copy
  }
}
