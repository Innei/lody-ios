import AppKit
import LodyCore
import LodyData

@MainActor
enum SessionControllerFactory {
  static func make(sessionId: String) -> MacSessionPane {
    let bridge = MacReplyBridge(sessionId: sessionId, sessions: .live)
    let pane = MacSessionController(
      sessionId: sessionId, source: .live(sessionId: sessionId, state: SessionPublished.state()), composer: bridge.composer
    )
    pane.retained = bridge
    pane.onFeed = { [weak bridge] in bridge?.update($0) }
    pane.onStreaming = { [weak bridge] in bridge?.setStreaming($0) }
    pane.onRetry = { [weak bridge] in bridge?.retry() }
    pane.pendingJSON = { [weak bridge] in bridge?.pendingJSON ?? "" }
    bridge.onPending = { [weak pane] in pane?.refreshPending() }
    return pane
  }
}
