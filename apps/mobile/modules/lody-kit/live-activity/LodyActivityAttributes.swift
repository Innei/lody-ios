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
        case permission, question, running, unread

        var priority: Int {
          switch self {
          case .question: 0
          case .permission: 1
          case .running: 2
          case .unread: 3
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

      var updatedDate: Date { Date(timeIntervalSince1970: updatedAt / 1000) }
    }

    struct PermissionAlert: Codable, Hashable, Sendable {
      var title: String
      var body: String
    }

    var totalCount: Int
    var statusCounts: Counts
    var items: [Item]
    var permissionAlert: PermissionAlert?

    private var ordered: [Item] {
      items.enumerated().sorted { left, right in
        if left.element.status.priority != right.element.status.priority {
          return left.element.status.priority < right.element.status.priority
        }
        if left.element.updatedAt != right.element.updatedAt {
          return left.element.updatedAt > right.element.updatedAt
        }
        return left.offset < right.offset
      }.map(\.element)
    }

    var focus: Item? { ordered.first }

    var others: [Item] { Array(ordered.dropFirst().prefix(2)) }

    var othersCount: Int { focus == nil ? 0 : max(totalCount - 1, 0) }

    var needsAttention: Bool {
      guard let status = focus?.status else { return false }
      return status == .question || status == .permission
    }

    var isActive: Bool {
      statusCounts.running + statusCounts.permission + statusCounts.question > 0
    }

    func staleDate(from updatedAt: Date) -> Date {
      updatedAt.addingTimeInterval(30 * 60)
    }

    func dismissalDate(from updatedAt: Date) -> Date? {
      guard !isActive, focus != nil else { return nil }
      return updatedAt.addingTimeInterval(15 * 60)
    }
  }

  var workspaceId: String
  var workspaceSlug: String
  var workspaceName: String
  var userId: String

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
