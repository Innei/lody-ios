import Foundation

@main
struct VerifyShareProbe {
  @MainActor
  static func main() async throws {
    let agent = ShareProbeAgent(id: "agent", name: "Agent", machineId: "machine", machineName: "Machine", cliType: "builtin", agentType: "test")
    func attempt() -> ShareProbeAttempt {
      ShareProbeAttempt(userId: "user", workspaceId: "workspace", agent: agent, text: "Please reply with OK.")
    }
    let failure = NSError(domain: "Injected", code: 1)

    var successful = attempt()
    var events: [String] = []
    let sessionId = successful.sessionId, sendId = successful.sendId
    let result = try await successful.submit(command: { method, args in
      events.append(method)
      assert(args["sessionId"] as? String == sessionId)
      if method == "createSession" { return ["state": "created", "session": ["id": sessionId]] }
      if method == "sendTurn" {
        assert(args["id"] as? String == sendId)
        assert(args["text"] as? String == "Please reply with OK.")
        return ["state": "accepted"]
      }
      return ["state": "watching"]
    }, persist: { value in events.append("saved:\(value.phase.rawValue)") })
    assert(result == .accepted)
    assert(events == ["saved:creating", "createSession", "saved:created", "ensureSession", "saved:sending", "sendTurn", "saved:accepted"])

    var noDisk = attempt()
    var requests = 0
    do {
      _ = try await noDisk.submit(command: { _, _ in requests += 1; return [:] }, persist: { _ in throw failure })
      fatalError("A failed receipt write must block submission")
    } catch {}
    assert(requests == 0)

    var lostCreateAck = attempt()
    requests = 0
    _ = try await lostCreateAck.submit(command: { method, _ in
      requests += 1
      assert(method == "createSession")
      return ["state": "unknown"]
    }, persist: { _ in })
    assert(lostCreateAck.phase == .unknown && requests == 1)
    // A recovered receipt must not restart creation, even after process death.
    var recovered = try JSONDecoder().decode(ShareProbeAttempt.self, from: JSONEncoder().encode(lostCreateAck))
    do {
      _ = try await recovered.submit(command: { _, _ in requests += 1; return [:] }, persist: { _ in })
      fatalError("Uncertain writes must not replay")
    } catch {}
    assert(requests == 1)

    for response in ["uploaded", "unknown", "not_sent"] {
      var pending = attempt()
      let pendingId = pending.sessionId
      _ = try await pending.submit(command: { method, _ in
        if method == "createSession" { return ["state": "created", "session": ["id": pendingId]] }
        if method == "sendTurn" { return ["state": response] }
        return ["state": "watching"]
      }, persist: { _ in })
      assert(pending.phase != .accepted, "An uploaded history entry is not a machine ACK")
    }

    var interrupted = attempt()
    let interruptedId = interrupted.sessionId
    events = []
    do {
      _ = try await interrupted.submit(command: { method, _ in
        events.append(method)
        if method == "createSession" { return ["state": "created", "session": ["id": interruptedId]] }
        throw failure
      }, persist: { _ in })
      fatalError("Session synchronization failed")
    } catch {}
    assert(interrupted.phase == .unknown)
    assert(events == ["createSession", "ensureSession"])

    var notWatching = attempt()
    let notWatchingId = notWatching.sessionId
    do {
      _ = try await notWatching.submit(command: { method, _ in
        if method == "createSession" { return ["state": "created", "session": ["id": notWatchingId]] }
        assert(method == "ensureSession", "Do not send before the session is watching")
        return ["state": "syncing"]
      }, persist: { _ in })
      fatalError("A non-ready session must block sending")
    } catch {}
    print("PASS: durable-before-write, create then send, stable IDs, uncertain ACKs never replay, upload is not delivery")
  }
}
