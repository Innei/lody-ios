import Foundation

@MainActor
public final class SessionControl {
  public struct State: Equatable, Sendable {
    public var running = false
    public var canStop = false
    public var controlling = false
    public var stopping = false
    public var steerID = ""
    public var steerInterrupts = false

    public init(running: Bool = false, canStop: Bool = false, controlling: Bool = false, stopping: Bool = false, steerID: String = "", steerInterrupts: Bool = false) {
      self.running = running
      self.canStop = canStop
      self.controlling = controlling
      self.stopping = stopping
      self.steerID = steerID
      self.steerInterrupts = steerInterrupts
    }
  }

  public typealias Request = @MainActor (_ payload: String) async throws -> String

  public var changed: (() -> Void)?
  private let request: Request
  private var inFlight = false
  private var busy = ""
  private var stoppedTurn = ""

  public init(request: @escaping Request) {
    self.request = request
  }

  public static let live: Request = { payload in
    guard let runtime = DataRuntime.current else { throw OutboxError.scopeExpired }
    return try await withCheckedThrowingContinuation { runtime.controlTurn(payload, sink: .continuation($0)) }
  }

  public func state(session: SessionItem, transcript: SessionTranscriptFacts, live: Bool, overflow: Bool, steerable: Bool) -> State {
    let turn = transcript.unfinishedTurnId
    let stopped = turn != nil && stoppedTurn == turn
    return State(
      running: turn != nil || OutboxDispatcher.busy.contains(session.status),
      canStop: canControl(session: session, transcript: transcript, live: live, overflow: overflow),
      controlling: stopped || (!busy.isEmpty && !transcript.delivered.contains(busy)),
      stopping: busy == "stop" || stopped,
      steerID: busy == "stop" ? "" : busy,
      steerInterrupts: !steerable
    )
  }

  public func act(_ action: String, messageId: String? = nil, session: SessionItem, transcript: SessionTranscriptFacts,
           live: Bool, overflow: Bool, steerable: Bool) {
    guard canControl(session: session, transcript: transcript, live: live, overflow: overflow), !inFlight,
          let turn = transcript.unfinishedTurnId else { return }
    inFlight = true
    busy = messageId ?? "stop"
    changed?()
    var payload: [String: Any] = [
      "action": action, "sessionId": session.id, "machineId": session.machineId, "turnId": turn,
      "interrupt": action == "steer" && !steerable,
    ]
    payload["messageId"] = messageId
    let request = request
    Task { @MainActor [weak self] in
      do {
        let result = try await request(RuntimeJSON.string(payload))
        let state = (try? JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])?["state"] as? String
        if state == "stopped" { self?.stoppedTurn = turn }
      } catch {
        LodyHosting.current?.toast(String(localized: "native.chat.composer.controlError", bundle: .lodyData), kind: "error")
      }
      self?.inFlight = false
      self?.busy = ""
      self?.changed?()
    }
  }

  private func canControl(session: SessionItem, transcript: SessionTranscriptFacts, live: Bool, overflow: Bool) -> Bool {
    guard let turn = transcript.unfinishedTurnId else { return false }
    return live && !session.archived && !overflow && busy.isEmpty && stoppedTurn != turn
  }
}
