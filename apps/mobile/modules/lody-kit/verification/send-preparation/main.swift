import Foundation

private actor Gate {
  private var blocked = false
  private var ready: CheckedContinuation<Void, Never>?
  private var waiting: CheckedContinuation<Void, Never>?

  func wait() async {
    blocked = true
    ready?.resume(); ready = nil
    await withCheckedContinuation { waiting = $0 }
  }
  func untilBlocked() async {
    if blocked { return }
    await withCheckedContinuation { ready = $0 }
  }
  func open() { waiting?.resume(); waiting = nil }
}

@main private struct VerifySendPreparation {
  @MainActor static func main() async {
    let preparation = SendPreparation()
    let gate = Gate()
    var writes = 0
    var cleanup: [String] = []
    var oldTaskCancelled = false
    let original = preparation.begin(session: "s", id: "first", generation: 1) { cleanup.append($0) }!
    let first = Task { @MainActor in
      await gate.wait()
      oldTaskCancelled = Task.isCancelled
      if preparation.owns(session: "s", token: original, generation: 1),
        preparation.finish(session: "s", token: original, generation: 1) { writes += 1 }
    }
    preparation.attach(first, session: "s", token: original, generation: 1)
    await gate.untilBlocked()
    precondition(!preparation.cancel(session: "s", id: "other", generation: 1, reason: "send_cancelled"))
    precondition(!preparation.cancel(session: "s", id: "first", generation: 2, reason: "send_cancelled"))
    precondition(preparation.cancel(session: "s", id: "first", generation: 1, reason: "send_cancelled"))
    precondition(preparation.count == 0 && first.isCancelled && cleanup == ["send_cancelled"], "Cancellation must immediately release ownership, its task and cleanup")
    precondition(!preparation.cancel(session: "s", id: "first", generation: 1, reason: "send_cancelled"))

    let replacement = preparation.begin(session: "s", id: "second", generation: 1) { cleanup.append($0) }!
    await gate.open()
    await first.value
    precondition(oldTaskCancelled && writes == 0, "A billing/upload callback arriving after cancellation cannot enter a runtime write")
    precondition(preparation.owns(session: "s", token: replacement, generation: 1), "An old callback cannot clear a newer attempt")
    precondition(!preparation.finish(session: "s", token: original, generation: 1))
    precondition(preparation.finish(session: "s", token: replacement, generation: 1))
    writes += 1
    precondition(!preparation.cancel(session: "s", id: "second", generation: 1, reason: "send_cancelled"), "After command entry cancellation must remain unconfirmed")
    precondition(writes == 1 && cleanup.count == 1)

    let stale = Task { @MainActor in }
    preparation.attach(stale, session: "s", token: original, generation: 1)
    precondition(stale.isCancelled, "A task installed after its ownership was removed is cancelled")
    await stale.value

    let teardownGate = Gate()
    let suspended = preparation.begin(session: "pending", id: "third", generation: 1) { cleanup.append($0) }!
    let pending = Task { @MainActor in
      await teardownGate.wait()
      precondition(Task.isCancelled)
      precondition(!preparation.owns(session: "pending", token: suspended, generation: 1))
    }
    preparation.attach(pending, session: "pending", token: suspended, generation: 1)
    _ = preparation.begin(session: "other", id: "fourth", generation: 1) { cleanup.append($0) }!
    await teardownGate.untilBlocked()
    preparation.cancelAll(reason: "runtime_replaced")
    precondition(preparation.count == 0 && pending.isCancelled && cleanup.count == 3, "Lifecycle teardown settles every owned preparation once")
    preparation.cancelAll(reason: "runtime_replaced")
    precondition(cleanup.count == 3)
    await teardownGate.open()
    await pending.value
    print("PASS: exact-send cancellation before awaited preparation, late callbacks, stale attempts, command boundary and lifecycle cleanup")
  }
}
