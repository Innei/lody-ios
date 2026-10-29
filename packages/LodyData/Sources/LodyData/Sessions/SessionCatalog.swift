import Foundation

public struct SessionPullRequest: Decodable, Equatable, Sendable {
  public var repository: String
  public var number: Int
  public var status: String
  public var ci: String?

  public init(repository: String, number: Int, status: String, ci: String? = nil) {
    self.repository = repository
    self.number = number
    self.status = status
    self.ci = ci
  }
}

public struct SessionItem: Equatable, Sendable {
  public var id: String
  public var title = ""
  public var status = "idle"
  public var archived = false
  public var pinned = false
  public var projectId = ""
  public var createdAt = ""
  public var openedBySessionId: String?
  public var openedByRootSessionId: String?
  public var parentSessionId: String?
  public var lastMessageAt: Double?
  public var lastReadAt: Double?
  public var awaitingUserSince: Double?
  public var branchName: String?
  public var modelName: String?
  public var modelNeverRan = false
  public var diff: [String: Int] = [:]
  public var lastViewedMessageAt: Double?
  public var machineId = ""
  public var cliType = ""
  public var agentType = ""
  public var resume: String?
  public var pullRequests: [SessionPullRequest] = []
  public var iosSimulatorPreviewRequestId: String?

  public var activityAt: Double { lastMessageAt ?? SessionItem.parse(createdAt) }

  private static func parse(_ value: String) -> Double {
    let precise = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    guard let date = (try? precise.parse(value)) ?? (try? Date.ISO8601FormatStyle().parse(value)) else { return .nan }
    return date.timeIntervalSince1970 * 1000
  }

  public init(id: String, title: String = "", status: String = "idle", archived: Bool = false, pinned: Bool = false, projectId: String = "", createdAt: String = "", openedBySessionId: String? = nil, openedByRootSessionId: String? = nil, parentSessionId: String? = nil, lastMessageAt: Double? = nil, lastReadAt: Double? = nil, awaitingUserSince: Double? = nil, branchName: String? = nil, modelName: String? = nil, modelNeverRan: Bool = false, diff: [String: Int] = [:], lastViewedMessageAt: Double? = nil, machineId: String = "", cliType: String = "", agentType: String = "", resume: String? = nil, pullRequests: [SessionPullRequest] = [], iosSimulatorPreviewRequestId: String? = nil) {
    self.id = id
    self.title = title
    self.status = status
    self.archived = archived
    self.pinned = pinned
    self.projectId = projectId
    self.createdAt = createdAt
    self.openedBySessionId = openedBySessionId
    self.openedByRootSessionId = openedByRootSessionId
    self.parentSessionId = parentSessionId
    self.lastMessageAt = lastMessageAt
    self.lastReadAt = lastReadAt
    self.awaitingUserSince = awaitingUserSince
    self.branchName = branchName
    self.modelName = modelName
    self.modelNeverRan = modelNeverRan
    self.diff = diff
    self.lastViewedMessageAt = lastViewedMessageAt
    self.machineId = machineId
    self.cliType = cliType
    self.agentType = agentType
    self.resume = resume
    self.pullRequests = pullRequests
    self.iosSimulatorPreviewRequestId = iosSimulatorPreviewRequestId
  }
}

extension SessionItem: Decodable {
  private enum CodingKeys: String, CodingKey {
    case id, title, status, archived, pinned, projectId, createdAt, openedBySessionId, openedByRootSessionId
    case parentSessionId, lastMessageAt, lastReadAt, awaitingUserSince, branchName, lastModel, diff, machineId
    case cliType, agentType, resume, pullRequests, iosSimulatorPreviewRequestId
  }

  private struct Model: Decodable {
    public var modelId: String?
    public var name: String?
  }

  private struct Diff: Decodable {
    public var add: Int?
    public var del: Int?
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    func present(_ text: String?) -> String? { text?.isEmpty == false ? text : nil }
    func value<T: Decodable>(_ key: CodingKeys) -> T? { (try? values.decodeIfPresent(T.self, forKey: key)) ?? nil }
    id = try values.decode(String.self, forKey: .id)
    title = value(.title) ?? ""
    status = value(.status) ?? "idle"
    archived = value(.archived) ?? false
    pinned = value(.pinned) ?? false
    projectId = value(.projectId) ?? ""
    createdAt = value(.createdAt) ?? ""
    openedBySessionId = present(value(.openedBySessionId))
    openedByRootSessionId = present(value(.openedByRootSessionId))
    parentSessionId = present(value(.parentSessionId))
    lastMessageAt = value(.lastMessageAt)
    lastReadAt = value(.lastReadAt)
    awaitingUserSince = value(.awaitingUserSince)
    branchName = present(value(.branchName))
    machineId = value(.machineId) ?? ""
    cliType = value(.cliType) ?? ""
    agentType = value(.agentType) ?? ""
    resume = present(value(.resume))
    pullRequests = value(.pullRequests) ?? []
    iosSimulatorPreviewRequestId = present(value(.iosSimulatorPreviewRequestId))
    modelNeverRan = values.contains(.lastModel) && ((try? values.decodeNil(forKey: .lastModel)) ?? false)
    if let model: Model = value(.lastModel) {
      modelName = [model.name, model.modelId].compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }
    if let diff: Diff = value(.diff), let add = diff.add, let del = diff.del { self.diff = ["add": add, "del": del] }
  }
}

public struct SessionProject: Decodable, Equatable, Sendable {
  public var id: String
  public var name = ""
  public var rootPath = ""
  public var machineId = ""
  public var repoFullName: String?

  private enum CodingKeys: String, CodingKey { case id, name, rootPath, repoFullName, machineId }

  public init(id: String, name: String = "", rootPath: String = "", repoFullName: String? = nil) {
    self.id = id
    self.name = name
    self.rootPath = rootPath
    self.repoFullName = repoFullName
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(String.self, forKey: .id)
    name = (try? values.decodeIfPresent(String.self, forKey: .name)) ?? ""
    rootPath = (try? values.decodeIfPresent(String.self, forKey: .rootPath)) ?? ""
    machineId = (try? values.decodeIfPresent(String.self, forKey: .machineId)) ?? ""
    repoFullName = (try? values.decodeIfPresent(String.self, forKey: .repoFullName)) ?? nil
  }
}

public struct SessionCatalog: Equatable, Sendable {
  public var projects: [SessionProject] = []
  public var sessions: [SessionItem] = []
  public var machineIds: [String] = []
  public var machineNames: [String: String] = [:]
  public var machineSimulators: [String: String] = [:]

  public func session(_ id: String) -> SessionItem? { sessions.first { $0.id == id } }

  public func viewed(_ views: [String: Double]) -> SessionCatalog {
    guard !views.isEmpty else { return self }
    var next = self
    next.sessions = sessions.map { session in
      var session = session
      session.lastViewedMessageAt = views[session.id]
      return session
    }
    return next
  }

  public static func decode(saved: Data, pending: [SessionItem] = []) -> SessionCatalog? {
    struct Shape: Decodable {
      public var projects: [Lossy<SessionProject>]
      public var sessions: [Lossy<SessionItem>]
      public var machineIds: [Lossy<String>]
      public var machineNames: Lossy<[String: String]>?
      public var machineSimulators: Lossy<[String: String]>?

      public init(projects: [Lossy<SessionProject>], sessions: [Lossy<SessionItem>], machineIds: [Lossy<String>], machineNames: Lossy<[String: String]>? = nil, machineSimulators: Lossy<[String: String]>? = nil) {
        self.projects = projects
        self.sessions = sessions
        self.machineIds = machineIds
        self.machineNames = machineNames
        self.machineSimulators = machineSimulators
      }
    }
    struct Saved: Decodable { var catalog: Shape }
    guard let shape = try? JSONDecoder().decode(Saved.self, from: saved).catalog else { return nil }
    return SessionCatalog(
      projects: shape.projects.compactMap(\.value), sessions: shape.sessions.compactMap(\.value) + pending,
      machineIds: shape.machineIds.compactMap(\.value), machineNames: shape.machineNames?.value ?? [:], machineSimulators: shape.machineSimulators?.value ?? [:]
    )
  }

  public init(projects: [SessionProject] = [], sessions: [SessionItem] = [], machineIds: [String] = [], machineNames: [String: String] = [:], machineSimulators: [String: String] = [:]) {
    self.projects = projects
    self.sessions = sessions
    self.machineIds = machineIds
    self.machineNames = machineNames
    self.machineSimulators = machineSimulators
  }
}

// A malformed entry is dropped rather than discarding the whole catalog.
public struct Lossy<T: Decodable>: Decodable {
  public var value: T?

  public init(from decoder: any Decoder) throws {
    value = try? T(from: decoder)
  }
}

extension Lossy: Sendable where T: Sendable {}
