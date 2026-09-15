import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

struct LodyActivityAttributes: Codable, Hashable, Sendable {
  struct ContentState: Codable, Hashable, Sendable {
    struct Counts: Codable, Hashable, Sendable {
      var permission: Int
      var question: Int
      var running: Int
      var unread: Int

      init(permission: Int = 0, question: Int = 0, running: Int = 0, unread: Int = 0) {
        self.permission = permission
        self.question = question
        self.running = running
        self.unread = unread
      }

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        permission = try container.decodeIfPresent(Int.self, forKey: .permission) ?? 0
        question = try container.decodeIfPresent(Int.self, forKey: .question) ?? 0
        running = try container.decodeIfPresent(Int.self, forKey: .running) ?? 0
        unread = try container.decodeIfPresent(Int.self, forKey: .unread) ?? 0
      }
    }

    struct Item: Codable, Hashable, Sendable {
      enum Status: String, Codable, Sendable {
        case permission, question, running, unread, failed

        var priority: Int {
          switch self {
          case .question: 0
          case .permission: 1
          case .running: 2
          case .unread: 3
          case .failed: 4
          }
        }
      }

      var id: String
      var status: Status
      var statusLabel: String
      var permissionRequestId: String?
      var permissionCommand: String?
      var agentLogoKind: String
      var agentLogoText: String
      var title: String
      var updatedAt: Double
      var updatedAtLabel: String
      var startedAt: Double?
      var completedAt: Double?

      var updatedDate: Date { Date(timeIntervalSince1970: updatedAt / 1000) }
      var startDate: Date { Date(timeIntervalSince1970: (startedAt ?? updatedAt) / 1000) }
      var completedDate: Date? { completedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
      var isDone: Bool { status == .unread || status == .failed }
    }

    struct PermissionAlert: Codable, Hashable, Sendable {
      var title: String
      var body: String
    }

    // The widget extension cannot read the app's catalog, so its own copy travels in
    // the state. Older payloads carry none and fall back to English.
    struct Copy: Codable, Hashable, Sendable {
      var stale: String
      var empty: String
      var others: String
      var lastSync: String
      var openHint: String
      var runningSummary: String?
      var completedSummary: String?
      var completedLabel: String?
      var failedLabel: String?
      var failedSummary: String?
      var elapsed: String?
      var waiting: String?
      var took: String?

      init(stale: String, empty: String, others: String, lastSync: String, openHint: String) {
        self.stale = stale
        self.empty = empty
        self.others = others
        self.lastSync = lastSync
        self.openHint = openHint
      }

      init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stale = try container.decodeIfPresent(String.self, forKey: .stale) ?? "Disconnected"
        empty = try container.decodeIfPresent(String.self, forKey: .empty) ?? "No active sessions"
        others = try container.decodeIfPresent(String.self, forKey: .others) ?? "{count} more running"
        lastSync = try container.decodeIfPresent(String.self, forKey: .lastSync) ?? "Last synced"
        openHint = try container.decodeIfPresent(String.self, forKey: .openHint) ?? "Tap to review"
        runningSummary = try container.decodeIfPresent(String.self, forKey: .runningSummary)
        completedSummary = try container.decodeIfPresent(String.self, forKey: .completedSummary)
        completedLabel = try container.decodeIfPresent(String.self, forKey: .completedLabel)
        failedLabel = try container.decodeIfPresent(String.self, forKey: .failedLabel)
        failedSummary = try container.decodeIfPresent(String.self, forKey: .failedSummary)
        elapsed = try container.decodeIfPresent(String.self, forKey: .elapsed)
        waiting = try container.decodeIfPresent(String.self, forKey: .waiting)
        took = try container.decodeIfPresent(String.self, forKey: .took)
      }
    }

    var totalCount: Int
    var statusCounts: Counts
    var items: [Item]
    var permissionAlert: PermissionAlert?
    var copy: Copy?

    var staleLabel: String { copy?.stale ?? "Disconnected" }

    var emptyLabel: String { copy?.empty ?? "No active sessions" }

    var lastSyncLabel: String { copy?.lastSync ?? "Last synced" }

    var openHintLabel: String { copy?.openHint ?? "Tap to review" }

    func othersLabel(_ count: Int) -> String {
      (copy?.others ?? "{count} more running")
        .replacingOccurrences(of: "{count}", with: "\(count)")
    }

    var elapsedCaption: String { copy?.elapsed ?? "elapsed" }

    var waitingCaption: String { copy?.waiting ?? "waiting" }

    var tookCaption: String { copy?.took ?? "took" }

    func completedSummary(_ count: Int) -> String {
      (copy?.completedSummary ?? "{count} tasks finished")
        .replacingOccurrences(of: "{count}", with: "\(count)")
    }

    func failedSummary(_ count: Int) -> String {
      (copy?.failedSummary ?? "{count} tasks failed")
        .replacingOccurrences(of: "{count}", with: "\(count)")
    }

    private var ordered: [Item] {
      items.sorted { left, right in
        if left.status.priority != right.status.priority {
          return left.status.priority < right.status.priority
        }
        return left.id < right.id
      }
    }

    var focus: Item? { ordered.first }

    var others: [Item] { Array(ordered.dropFirst().prefix(2)) }

    var activeCount: Int { statusCounts.running + statusCounts.permission + statusCounts.question }

    var othersCount: Int { focus == nil ? 0 : max(activeCount - 1, 0) }

    var showsOverview: Bool { activeCount > 1 && !needsAttention }

    var completedItems: [Item] { items.filter(\.isDone) }

    var isCompleted: Bool { !isActive && !completedItems.isEmpty }

    var allFailed: Bool { isCompleted && completedItems.allSatisfy { $0.status == .failed } }

    var visibleItems: [Item] { Array(ordered.prefix(2)) }

    var runningSummary: String {
      (copy?.runningSummary ?? "{count} running")
        .replacingOccurrences(of: "{count}", with: "\(statusCounts.running)")
    }

    var needsAttention: Bool {
      guard let status = focus?.status else { return false }
      return status == .question || status == .permission
    }

    var isActive: Bool {
      activeCount > 0
    }

    func timerCaption(for item: Item) -> String {
      switch item.status {
      case .unread, .failed: tookCaption
      case .permission, .question: waitingCaption
      case .running: elapsedCaption
      }
    }

    func showsTimer(for item: Item, isStale: Bool) -> Bool {
      if isStale { return false }
      return !item.isDone || item.startedAt != nil
    }

    func staleDate(from updatedAt: Date) -> Date {
      updatedAt.addingTimeInterval(30 * 60)
    }

    func dismissalDate(from updatedAt: Date) -> Date? {
      guard !isActive else { return nil }
      return updatedAt.addingTimeInterval(60)
    }
  }

  var workspaceId: String
  var workspaceSlug: String
  var workspaceName: String
  var userId: String

  init(workspaceId: String, workspaceSlug: String, workspaceName: String, userId: String) {
    self.workspaceId = workspaceId
    self.workspaceSlug = workspaceSlug
    self.workspaceName = workspaceName
    self.userId = userId
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    workspaceId = try container.decode(String.self, forKey: .workspaceId)
    workspaceSlug = try container.decodeIfPresent(String.self, forKey: .workspaceSlug) ?? ""
    workspaceName = try container.decode(String.self, forKey: .workspaceName)
    userId = try container.decode(String.self, forKey: .userId)
  }

  var routeSlug: String { workspaceSlug.isEmpty ? workspaceId : workspaceSlug }

  var overviewRoute: URL {
    var url = URLComponents()
    url.scheme = "lody"
    url.host = ""
    url.path = "/activity"
    url.queryItems = [URLQueryItem(name: "workspaceId", value: workspaceId), URLQueryItem(name: "userId", value: userId)]
    return url.url!
  }

  func route(for state: ContentState) -> URL {
    guard !state.showsOverview, let focus = state.focus else { return overviewRoute }
    return Self.route(workspaceSlug: routeSlug, sessionId: focus.id)
  }

  static func route(workspaceSlug: String, sessionId: String) -> URL {
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
    let slug = workspaceSlug.addingPercentEncoding(withAllowedCharacters: allowed) ?? workspaceSlug
    let session = sessionId.addingPercentEncoding(withAllowedCharacters: allowed) ?? sessionId
    return URL(string: "lody:///\(slug)/sessions/\(session)")!
  }
}

#if canImport(ActivityKit)
extension LodyActivityAttributes: ActivityAttributes {}
#endif
