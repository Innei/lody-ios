import Foundation

/// Tracks SDK submissions, never network acknowledgements. In OneSignal 5.5.1
/// enter/exit callbacks only acknowledge enqueueing; identical tokens are cached.
@MainActor
final class LiveActivityRegistration {
  private struct Binding {
    let stamp: UUID
    var token: Data?
  }
  private var bindings: [String: Binding] = [:]
  private var lastRecovery: TimeInterval?
  private let enterSDK: (String, Data) -> Void
  private let exitSDK: (String) -> Void
  private let restartSDK: () -> Void
  private let now: () -> TimeInterval

  init(enter: @escaping (String, Data) -> Void, exit: @escaping (String) -> Void,
       restart: @escaping () -> Void, now: @escaping () -> TimeInterval) {
    enterSDK = enter
    exitSDK = exit
    restartSDK = restart
    self.now = now
  }

  func observe(_ id: String, stamp: UUID) {
    // A new native instance replaces the update token under the same server ID.
    // Do not enqueue exit: its HTTP DELETE could arrive after the new token POST.
    bindings[id] = Binding(stamp: stamp)
  }

  func enter(_ id: String, token: Data, stamp: UUID) {
    guard var binding = bindings[id], binding.stamp == stamp, binding.token != token else { return }
    binding.token = token
    bindings[id] = binding
    enterSDK(id, token)
    recoverPendingRequests()
  }

  func exit(_ id: String) {
    bindings.removeValue(forKey: id)
    exitSDK(id)
    recoverPendingRequests()
  }

  func recover() {
    // Re-submit live tokens in case the SDK discarded a terminally failed request.
    // Cached identical tokens are ignored by the SDK, so also drive its pending
    // request poll; enqueue callbacks cannot tell us whether registration worked.
    for (id, binding) in bindings {
      if let token = binding.token { enterSDK(id, token) }
    }
    recoverPendingRequests()
  }

  private func recoverPendingRequests() {
    let time = now()
    if let lastRecovery, time - lastRecovery < 30 { return }
    lastRecovery = time
    // The pinned SDK's public start hook schedules one pending-cache poll after
    // 30 seconds. It does not loop. Bound foreground/readiness bursts to one poll.
    restartSDK()
  }
}
