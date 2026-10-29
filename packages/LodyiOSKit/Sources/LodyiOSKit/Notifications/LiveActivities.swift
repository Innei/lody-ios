import ActivityKit
import Foundation
import os
import OneSignalFramework
import OneSignalLiveActivities
import UIKit

@MainActor
final class LiveActivities {
  static let shared = LiveActivities()
  private let defaults = UserDefaults(suiteName: "group.app.innei.lody")
  private var tokenTasks: [String: (stamp: UUID, nativeId: String, task: Task<Void, Never>, lifecycle: Task<Void, Never>, content: Task<Void, Never>)] = [:]
  private var lastContentLog: [String: (signature: String, time: Date)] = [:]
  private var pushToStartTask: Task<Void, Never>?
  private var activityTask: Task<Void, Never>?
  private var syncTask: Task<Void, Never>?
  private var workStarts: [String: Double] = [:]
  private var userId: String?
  private var identityResolved = false
  private lazy var registrations = LiveActivityRegistration(
    enter: { id, token in
      OneSignal.LiveActivities.enter(id, withToken: Self.hex(token))
      Self.diagnostic("enter_submitted", id: id)
    },
    exit: { id in
      OneSignal.LiveActivities.exit(id)
      Self.diagnostic("exit_submitted", id: id)
    },
    restart: {
      // 5.5.1 retains retryable failures in its cache but needs another start
      // to poll them. Re-entering an identical cached token alone is a no-op.
      OneSignalLiveActivitiesManagerImpl.start()
      Self.diagnostic("registration_recovery_requested")
    },
    now: { ProcessInfo.processInfo.systemUptime }
  )

  func syncAppIcon() {
    let name = UIApplication.shared.alternateIconName ?? "default"
    guard LodyActivityIcon.defaults?.string(forKey: LodyActivityIcon.key) != name else { return }
    LodyActivityIcon.defaults?.set(name, forKey: LodyActivityIcon.key)
    Self.refreshAppIcon()
  }

  private nonisolated static func refreshAppIcon() {
    Task {
      for activity in Activity<LodyActivityAttributes>.activities
        where activity.activityState == .active || activity.activityState == .stale {
        let content = activity.content
        var state = content.state
        state.appIcon = LodyActivityIcon.name
        await activity.update(ActivityContent(state: state, staleDate: content.staleDate, relevanceScore: content.relevanceScore))
      }
    }
  }

  var enabled: Bool {
    get { defaults?.object(forKey: "liveActivitiesEnabled") as? Bool ?? true }
    set {
      defaults?.set(newValue, forKey: "liveActivitiesEnabled")
      if newValue {
        start()
        return
      }
      endAll(reason: "toggle_off")
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
    diagnosticSnapshot("start")
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    registerPushToStart()
    observeCurrentActivities()
    guard activityTask == nil else { return }
    activityTask = Task { @MainActor in
      for await activity in Activity<LodyActivityAttributes>.activityUpdates { observe(activity) }
    }
  }

  func recoverRegistrations() {
    start()
    guard PushNotifications.shared.configured else { return }
    // Lifecycle streams may resume after this foreground callback. Fence ended
    // or dismissed native instances before re-submitting their cached tokens.
    let live = Set(Activity<LodyActivityAttributes>.activities.filter {
      enabled && ActivityAuthorizationInfo().areActivitiesEnabled &&
        $0.attributes.userId == userId && ($0.activityState == .active || $0.activityState == .stale)
    }.map(\.id))
    for (id, observation) in tokenTasks where !live.contains(observation.nativeId) {
      unregister(id, reason: "recovery_not_active")
    }
    registrations.recover()
  }

  // Called before OneSignal switches identity to invalidate old observers and queue cleanup.
  func identify(_ id: String?) {
    // On a push-to-start cold launch, SDK identity restoration can trail ActivityKit.
    // Preserve a matching server-started activity until app auth resolves its owner.
    if !identityResolved {
      identityResolved = true
      userId = id
      if id == nil {
        removePushToStart()
        endAll(reason: "identity_missing")
      }
      return
    }
    guard userId != id || id == nil else { return }
    removePushToStart()
    endAll(reason: "identity_changed")
    userId = id
  }

  private func removePushToStart() {
    pushToStartTask?.cancel()
    pushToStartTask = nil
    guard PushNotifications.shared.configured else { return }
    Self.diagnostic("push_to_start_remove")
    OneSignal.LiveActivities.removePushToStartToken(LodyActivityAttributes.self)
  }

  private func registerPushToStart() {
    guard PushNotifications.shared.configured, let owner = userId, !owner.isEmpty,
          enabled, pushToStartTask == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    pushToStartTask = Task { @MainActor in
      guard !Task.isCancelled, enabled, userId == owner else { return }
      if let token = Activity<LodyActivityAttributes>.pushToStartToken {
        Self.diagnostic("push_to_start_token", fields: ["source": "current"])
        OneSignal.LiveActivities.setPushToStartToken(LodyActivityAttributes.self, withToken: Self.hex(token))
      }
      for await token in Activity<LodyActivityAttributes>.pushToStartTokenUpdates {
        guard !Task.isCancelled, enabled, userId == owner else { return }
        Self.diagnostic("push_to_start_token", fields: ["source": "stream"])
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
    if !state.isActive, Activity<LodyActivityAttributes>.activities.contains(where: {
      Self.id(of: $0) == id && ($0.activityState == .active || $0.activityState == .stale)
    }) {
      Self.diagnostic("catalog_inactive", id: id, fields: ["sessions": String(sessions.count)])
    }
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
        diagnostic("end_requested", id: id, fields: ["reason": "catalog_inactive", "native": correlation(activity.id)])
        if !isDebug(attributes) { await shared.unregister(id, reason: "catalog_inactive") }
        let ended = completed(summary, previous: activity.content.state, failed: failed, at: now)
        await activity.end(ActivityContent(state: ended, staleDate: nil), dismissalPolicy: .after(state.dismissalDate(from: now) ?? now))
      }
    }
    guard !Task.isCancelled, existing.isEmpty, state.isActive else { return }
    for activity in Activity<LodyActivityAttributes>.activities where activityId(of: activity.attributes) == id && activity.activityState == .ended {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    guard !Task.isCancelled else { return }
    diagnostic("create_requested", id: id, fields: ["active": String(state.activeCount)])
    do {
      let activity = try Activity.request(attributes: attributes, content: content, pushType: isDebug(attributes) ? nil : .token)
      diagnostic("created", id: id, fields: ["native": correlation(activity.id), "active": String(state.activeCount)])
      if Task.isCancelled {
        diagnostic("end_requested", id: id, fields: ["reason": "create_cancelled", "native": correlation(activity.id)])
        await activity.end(nil, dismissalPolicy: .immediate)
      } else {
        await shared.observeCurrentActivities()
      }
    } catch {
      diagnostic("create_failed", id: id, fields: ["code": String((error as NSError).code)])
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

  // Correlates with Convex's SHA-256 prefix; never hash or log an APNs token.
  private nonisolated static func correlation(_ value: String) -> String {
    DiagnosticsStore.correlation(value)
  }

  private nonisolated static func diagnostic(_ event: StaticString, id: String? = nil, fields: [String: String] = [:]) {
    var record = fields
    if let id { record["activity"] = correlation(id) }
    DiagnosticsStore.shared.record("live-activity", event, fields: record)
    record["event"] = event.description
    guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
          let line = String(data: data, encoding: .utf8) else { return }
    // Notice persists across suspension; SDK verbose logs can contain tokens.
    log.notice("\(line, privacy: .public)")
  }

  func diagnosticSnapshot(_ reason: String) {
    Self.diagnostic("snapshot", fields: [
      "reason": reason, "enabled": String(enabled), "identified": String(userId != nil),
      "authorized": String(ActivityAuthorizationInfo().areActivitiesEnabled),
      "appState": String(UIApplication.shared.applicationState.rawValue),
      "observed": String(tokenTasks.count), "activities": String(Activity<LodyActivityAttributes>.activities.count),
      "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
      "oneSignalApp": Bundle.main.object(forInfoDictionaryKey: "LodyOneSignalAppId") as? String ?? "none",
    ])
    for activity in Activity<LodyActivityAttributes>.activities {
      Self.diagnostic("activity_snapshot", id: Self.id(of: activity), fields: [
        "native": Self.correlation(activity.id), "state": String(describing: activity.activityState),
        "hasToken": String(activity.pushToken != nil), "active": String(activity.content.state.activeCount),
        "serverUpdatedAt": String(activity.content.state.updatedAt ?? 0),
        "staleDate": String(activity.content.staleDate?.timeIntervalSince1970 ?? 0),
      ])
    }
  }

  private func unregister(_ id: String, reason: String) {
    Self.diagnostic("unregister", id: id, fields: ["reason": reason])
    stopObserving(id)
    registrations.exit(id)
  }

  private func stopObserving(_ id: String) {
    if let observation = tokenTasks.removeValue(forKey: id) {
      observation.task.cancel()
      observation.lifecycle.cancel()
      observation.content.cancel()
    }
    lastContentLog.removeValue(forKey: id)
  }

  func endAll(reason: String = "explicit_end_all") {
    syncTask?.cancel()
    let ids = Set(tokenTasks.keys).union(Activity<LodyActivityAttributes>.activities
      .filter { !Self.isDebug($0.attributes) }.map { Self.id(of: $0) })
    for id in ids { unregister(id, reason: reason) }
    Self.diagnostic("end_all", fields: ["reason": reason, "count": String(ids.count)])
    Self.endActivities()
    workStarts = [:]
  }

  private func endStale(keeping id: String) {
    var stale = false
    for activity in Activity<LodyActivityAttributes>.activities where !Self.isDebug(activity.attributes) {
      let other = Self.id(of: activity)
      guard other != id else { continue }
      stale = true
      unregister(other, reason: "workspace_changed")
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
      Self.diagnostic("end_requested", id: id, fields: ["reason": "owner_or_toggle_rejected", "native": Self.correlation(nativeId)])
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
      stopObserving(id)
    }
    let stamp = UUID()
    registrations.observe(id, stamp: stamp)
    Self.diagnostic("observe", id: id, fields: ["native": Self.correlation(activity.id), "hasToken": String(activity.pushToken != nil)])
    let tokens = Task { @MainActor in
      guard !Task.isCancelled, enabled, userId == owner else { return }
      if let token = activity.pushToken {
        register(id, token: token, stamp: stamp)
      }
      for await token in activity.pushTokenUpdates {
        guard !Task.isCancelled, enabled, userId == owner else { return }
        register(id, token: token, stamp: stamp)
      }
    }
    let lifecycle = Task { @MainActor in
      for await state in activity.activityStateUpdates {
        guard !Task.isCancelled, tokenTasks[id]?.stamp == stamp else { return }
        Self.diagnostic("lifecycle", id: id, fields: ["state": String(describing: state), "native": Self.correlation(activity.id)])
        if state == .ended || state == .dismissed {
          unregister(id, reason: "system_\(state)")
          return
        }
      }
    }
    let content = Task { @MainActor in
      for await content in activity.contentUpdates {
        guard !Task.isCancelled, tokenTasks[id]?.stamp == stamp else { return }
        // Local catalog writes can be frequent. Log changed counts immediately,
        // otherwise at most once/minute. Observation is not an APNs receipt.
        let state = content.state
        let signature = "\(state.statusCounts):\(state.updatedAt ?? 0)"
        let now = Date()
        if let previous = lastContentLog[id], previous.signature == signature,
           now.timeIntervalSince(previous.time) < 60 { continue }
        lastContentLog[id] = (signature, now)
        Self.diagnostic("content_observed", id: id, fields: [
          "native": Self.correlation(activity.id), "active": String(state.activeCount),
          "unread": String(state.statusCounts.unread), "serverUpdatedAt": String(state.updatedAt ?? 0),
          "staleDate": String(content.staleDate?.timeIntervalSince1970 ?? 0),
          "appState": String(UIApplication.shared.applicationState.rawValue),
        ])
      }
    }
    tokenTasks[id] = (stamp, activity.id, tokens, lifecycle, content)
  }

  private func register(_ id: String, token: Data, stamp: UUID) {
    guard tokenTasks[id]?.stamp == stamp else { return }
    registrations.enter(id, token: token, stamp: stamp)
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
      permission: String(localized: "native.liveActivity.status.attention", bundle: .lody),
      running: String(localized: "native.liveActivity.status.running", bundle: .lody),
      stale: String(localized: "native.liveActivity.stale", bundle: .lody),
      empty: String(localized: "native.liveActivity.empty", bundle: .lody),
      others: String(localized: "native.liveActivity.others", bundle: .lody),
      lastSync: String(localized: "native.liveActivity.lastSync", bundle: .lody),
      openHint: String(localized: "native.liveActivity.openHint", bundle: .lody),
      runningSummary: String(localized: "native.liveActivity.runningSummary", bundle: .lody),
      completedSummary: String(localized: "native.liveActivity.completedSummary", bundle: .lody),
      completed: String(localized: "native.liveActivity.status.unread", bundle: .lody),
      failed: String(localized: "native.liveActivity.status.failed", bundle: .lody),
      failedSummary: String(localized: "native.liveActivity.failedSummary", bundle: .lody),
      elapsed: String(localized: "native.liveActivity.caption.elapsed", bundle: .lody),
      waiting: String(localized: "native.liveActivity.caption.waiting", bundle: .lody),
      took: String(localized: "native.liveActivity.caption.took", bundle: .lody),
      smallAttention: String(localized: "native.liveActivity.small.attention", bundle: .lody),
      smallWaiting: String(localized: "native.liveActivity.small.waiting", bundle: .lody),
      smallDone: String(localized: "native.liveActivity.small.done", bundle: .lody),
      smallFailed: String(localized: "native.liveActivity.small.failed", bundle: .lody),
      smallStale: String(localized: "native.liveActivity.small.stale", bundle: .lody)
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
      title: LocalizedStringResource(stringLiteral: String(localized: "native.liveActivity.debug.alertTitle", bundle: .lody)),
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
      statusLabel: String(localized: String.LocalizationValue("native.liveActivity.status." + status.rawValue), bundle: .lody),
      permissionRequestId: command == nil ? nil : "debug-request",
      permissionCommand: command,
      agentLogoKind: agent == "CC" ? "claude" : "codex",
      agentLogoText: agent,
      title: title,
      updatedAt: updatedAt,
      updatedAtLabel: String(localized: "native.liveActivity.debug.updatedAt", bundle: .lody),
      startedAt: updatedAt - startedAgo * 1000
    )
  }

  private nonisolated static func debugState(permission: Bool = false) -> LodyActivityAttributes.ContentState {
    let now = Date().timeIntervalSince1970 * 1000
    let second = debugItem(
      "debug-2",
      permission ? .permission : .running,
      String(localized: "native.liveActivity.debug.title2", bundle: .lody),
      "CX",
      now - 1000,
      startedAgo: 187,
      command: permission ? "git push origin main --force" : nil
    )
    return LodyActivityAttributes.ContentState(
      totalCount: 2,
      statusCounts: .init(permission: permission ? 1 : 0, running: permission ? 1 : 2),
      items: [
        debugItem("debug-1", .running, String(localized: "native.liveActivity.debug.title1", bundle: .lody), "CC", now, startedAgo: 761),
        second,
      ],
      permissionAlert: permission
        ? .init(title: String(localized: "native.liveActivity.debug.alertTitle", bundle: .lody), body: "git push origin main --force")
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
    copy.smallAttention = labels.smallAttention
    copy.smallWaiting = labels.smallWaiting
    copy.smallDone = labels.smallDone
    copy.smallFailed = labels.smallFailed
    copy.smallStale = labels.smallStale
    return copy
  }
}
