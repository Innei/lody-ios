import Foundation

public struct OutboxPersistence: Sendable {
  public var generation: @Sendable () -> Int
  public var read: @Sendable (String) async -> String?
  public var write: @Sendable (_ key: String, _ value: String, _ generation: Int) async throws -> Void

  public init(generation: @escaping @Sendable () -> Int, read: @escaping @Sendable (String) async -> String?, write: @escaping @Sendable (_ key: String, _ value: String, _ generation: Int) async throws -> Void) {
    self.generation = generation
    self.read = read
    self.write = write
  }
}

public enum OutboxError: Error, Equatable, Sendable {
  case scopeExpired
  case invalidRecord
}

@MainActor
public final class OutboxStore {
  public struct Snapshot: Equatable, Sendable {
    public var records: [OutboxRecord] = []
    public var ready = false

    public init(records: [OutboxRecord] = [], ready: Bool = false) {
      self.records = records
      self.ready = ready
    }
  }

  public let key: String
  public let generation: Int
  public private(set) var snapshot = Snapshot()
  public private(set) var revision = 0
  public var onChange: (() -> Void)?
  private let persistence: OutboxPersistence
  private var durable: [OutboxRecord] = []
  private var touched = Set<String>()
  private var writes: Task<Void, Never>

  public init(key: String, generation: Int, persistence: OutboxPersistence, awaitingConfirmation: String) {
    self.key = key
    self.generation = generation
    self.persistence = persistence
    writes = Task {}
    writes = Task { @MainActor [weak self] in
      let saved = await persistence.read(key)
      guard let self, generation == persistence.generation() else { return }
      self.durable = OutboxRecord.restore(saved, awaitingConfirmation: awaitingConfirmation)
      let restored = self.durable.filter { !self.touched.contains($0.sessionId) }
      self.publish(restored + self.snapshot.records, ready: true)
    }
  }

  public var json: String {
    let records = OutboxRecord.encode(snapshot.records)
    return #"{"ready":\#(snapshot.ready),"records":\#(records)}"#
  }

  @discardableResult
  public func put(_ record: OutboxRecord) -> Task<Void, Error> {
    change(record.sessionId, record)
  }

  @discardableResult
  public func remove(_ sessionId: String) -> Task<Void, Error> {
    change(sessionId, nil)
  }

  private var current: Bool { generation == persistence.generation() }

  private func change(_ sessionId: String, _ record: OutboxRecord?) -> Task<Void, Error> {
    guard current else { return Task { throw OutboxError.scopeExpired } }
    touched.insert(sessionId)
    publish(Self.replace(snapshot.records, sessionId, record), ready: snapshot.ready)
    let previous = writes, key = key, generation = generation, persistence = persistence
    let write = Task { @MainActor [weak self] in
      await previous.value
      guard let self, self.current else { throw OutboxError.scopeExpired }
      let next = Self.replace(self.durable, sessionId, record)
      try await persistence.write(key, OutboxRecord.encode(next), generation)
      guard self.current else { throw OutboxError.scopeExpired }
      self.durable = next
    }
    writes = Task { _ = await write.result }
    return write
  }

  private static func replace(_ records: [OutboxRecord], _ sessionId: String, _ record: OutboxRecord?) -> [OutboxRecord] {
    var next = records.filter { $0.sessionId != sessionId }
    if let record { next.append(record) }
    return next
  }

  private func publish(_ records: [OutboxRecord], ready: Bool) {
    snapshot = Snapshot(records: records, ready: ready)
    revision += 1
    onChange?()
  }
}

@MainActor
public final class OutboxStores {
  private let persistence: OutboxPersistence
  private let awaitingConfirmation: () -> String
  private var stores: [String: OutboxStore] = [:]
  private var generation: Int
  public var onChange: ((OutboxStore) -> Void)?
  public var onReset: (() -> Void)?

  public init(persistence: OutboxPersistence, awaitingConfirmation: @escaping () -> String) {
    self.persistence = persistence
    self.awaitingConfirmation = awaitingConfirmation
    generation = persistence.generation()
  }

  public nonisolated static func key(user: String, workspace: String) -> String {
    user.isEmpty || workspace.isEmpty ? "" : "pending-sends:\(user):\(workspace)"
  }

  public func store(user: String, workspace: String) -> OutboxStore? {
    let current = persistence.generation()
    if generation != current {
      stores.removeAll()
      generation = current
      onReset?()
    }
    let key = Self.key(user: user, workspace: workspace)
    guard !key.isEmpty else { return nil }
    if let store = stores[key] { return store }
    let store = OutboxStore(key: key, generation: current, persistence: persistence, awaitingConfirmation: awaitingConfirmation())
    store.onChange = { [weak self, unowned store] in self?.onChange?(store) }
    stores[key] = store
    return store
  }
}
