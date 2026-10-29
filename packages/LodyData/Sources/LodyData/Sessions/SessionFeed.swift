import Foundation

public struct SessionRuntimeEvent: Sendable {
  public var generation = -1
  public var state = ""
  public var sessionId: String?
  public var session: String?

  public init(generation: Int = -1, state: String = "", sessionId: String? = nil, session: String? = nil) {
    (self.generation, self.state, self.sessionId, self.session) = (generation, state, sessionId, session)
  }

  public init(_ info: [AnyHashable: Any]) {
    self.init(
      generation: (info["generation"] as? NSNumber)?.intValue ?? -1, state: info["state"] as? String ?? "",
      sessionId: info["sessionId"] as? String, session: info["session"] as? String
    )
  }
}

public struct SessionFeedState: Equatable, Sendable {
  public var status = "syncing"
  public var revision = -1
  public var overflow = false
  public var entriesJSON = "[]"
  public var billableTurnCount: Int?
  public var composerJSON: String?
  public var preview: SessionBrowserPreview?
  public var transcript = SessionTranscriptFacts()

  public init(status: String = "syncing", revision: Int = -1, overflow: Bool = false, entriesJSON: String = "[]", billableTurnCount: Int? = nil, composerJSON: String? = nil, preview: SessionBrowserPreview? = nil, transcript: SessionTranscriptFacts = SessionTranscriptFacts()) {
    self.status = status
    self.revision = revision
    self.overflow = overflow
    self.entriesJSON = entriesJSON
    self.billableTurnCount = billableTurnCount
    self.composerJSON = composerJSON
    self.preview = preview
    self.transcript = transcript
  }
}

@MainActor
public struct SessionFeedService: Sendable {
  public var watch: @MainActor (_ sessionId: String, _ receive: @escaping @MainActor (SessionRuntimeEvent) -> Void) -> @MainActor () -> Void
  public var reconnect: @MainActor (_ sessionId: String) -> Void
  public var cached: @Sendable (_ userId: String, _ workspaceId: String, _ sessionId: String) -> String?

  public static let live = SessionFeedService(
    watch: { sessionId, receive in
      let observer = NotificationCenter.default.addObserver(forName: .lodyDataRuntimeEvent, object: nil, queue: .main) { note in
        let event = SessionRuntimeEvent(note.userInfo ?? [:])
        MainActor.assumeIsolated { receive(event) }
      }
      DataRuntime.current?.openSession(sessionId)
      return {
        NotificationCenter.default.removeObserver(observer)
        DataRuntime.current?.closeSession(sessionId)
      }
    },
    reconnect: { DataRuntime.current?.openSession($0) },
    cached: { userId, workspaceId, sessionId in
      guard let data = try? JSONSerialization.data(withJSONObject: [userId, workspaceId, sessionId], options: .withoutEscapingSlashes)
      else { return nil }
      return try? LocalStore.shared.read("session:" + String(decoding: data, as: UTF8.self))
    }
  )

  public init(watch: @escaping @MainActor (_ sessionId: String, _ receive: @escaping @MainActor (SessionRuntimeEvent) -> Void) -> @MainActor () -> Void, reconnect: @escaping @MainActor (_ sessionId: String) -> Void, cached: @escaping @Sendable (_ userId: String, _ workspaceId: String, _ sessionId: String) -> String?) {
    self.watch = watch
    self.reconnect = reconnect
    self.cached = cached
  }
}

@MainActor
public final class SessionFeed {
  public private(set) var state = SessionFeedState()
  public var changed: (() -> Void)?
  private let service: SessionFeedService
  private let sessionId: String
  private let userId: String
  private let workspaceId: String
  private var cursor = (generation: -1, revision: -1)
  private var received = false
  private var unwatch: (@MainActor () -> Void)?
  private var token = 0
  private static let parsing = DispatchQueue(label: "app.innei.lody.session-feed", qos: .userInitiated)

  public init(sessionId: String, userId: String, workspaceId: String, service: SessionFeedService = .live) {
    self.sessionId = sessionId
    self.userId = userId
    self.workspaceId = workspaceId
    self.service = service
  }

  public var watching: Bool { unwatch != nil }
  public var generation: Int { cursor.generation }

  public func start() {
    guard unwatch == nil, !userId.isEmpty, !workspaceId.isEmpty else { return }
    token += 1
    cursor = (-1, -1)
    received = false
    state = SessionFeedState()
    changed?()
    let token = token
    let (cached, userId, workspaceId, sessionId) = (service.cached, userId, workspaceId, sessionId)
    LocalStore.queue.async {
      let saved = cached(userId, workspaceId, sessionId).flatMap(SessionEnvelope.prepare)
      DispatchQueue.main.async {
        MainActor.assumeIsolated { [weak self] in
          guard let self, self.token == token, !self.received, let saved, saved.version == 1 else { return }
          self.state.entriesJSON = saved.entriesJSON
          self.state.transcript = saved.transcript
          self.state.preview = saved.preview
          self.changed?()
        }
      }
    }
    unwatch = service.watch(sessionId) { [weak self] event in self?.receive(event) }
  }

  public func finish() {
    token += 1
    unwatch?()
    unwatch = nil
  }

  public func reconnect() {
    guard unwatch != nil else { return }
    service.reconnect(sessionId)
  }

  private func receive(_ event: SessionRuntimeEvent) {
    let token = token
    let generation = event.generation
    let session = event.sessionId == sessionId ? event.session : nil
    let phase = event.state
    // Parsing runs off the main thread; status-only events take the same queue to keep arrival order.
    Self.parsing.async {
      let envelope = session.map(SessionEnvelope.prepare)
      DispatchQueue.main.async {
        MainActor.assumeIsolated { [weak self] in
          guard let self, self.token == token else { return }
          if let envelope {
            self.apply(envelope, generation: generation)
          } else if ["starting", "background", "failed", "stopped"].contains(phase) {
            self.state.status = phase
            self.changed?()
          }
        }
      }
    }
  }

  private func apply(_ envelope: SessionEnvelope?, generation: Int) {
    guard let envelope else {
      state.status = "offline"
      changed?()
      return
    }
    if envelope.overflow, envelope.version == 1 {
      state.overflow = true
      changed?()
      return
    }
    guard envelope.accepted(generation: generation, after: cursor), let revision = envelope.revision else { return }
    cursor = (generation, revision)
    state.overflow = false
    if envelope.status == "live" {
      received = true
      state = SessionFeedState(
        status: "live", revision: revision, entriesJSON: envelope.entriesJSON,
        billableTurnCount: envelope.billableTurnCount, composerJSON: envelope.composerJSON, preview: envelope.preview, transcript: envelope.transcript
      )
    } else {
      state.status = envelope.status
    }
    changed?()
  }
}

extension Notification.Name {
  public static let lodyDataRuntimeEvent = Notification.Name("LodyDataRuntimeEvent")
}
