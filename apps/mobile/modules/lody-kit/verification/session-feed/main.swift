import Foundation

// The production feed owns its subscription; these stubs only remove app I/O.
final class LocalStore: @unchecked Sendable {
  static let shared = LocalStore()
  static let queue = DispatchQueue(label: "fixture-cache")
  func read(_ key: String) throws -> String? { nil }
}
@MainActor final class DataRuntime {
  static var current: DataRuntime?
  func openSession(_ id: String) { preconditionFailure("Unexpected live runtime") }
  func closeSession(_ id: String) { preconditionFailure("Unexpected live runtime") }
}
@MainActor final class Fixture {
  var receive: ((SessionRuntimeEvent) -> Void)?
  var watched = 0
  var unwatched = 0
  var reconnects = 0
  nonisolated static func envelope(_ revision: Int, _ text: String) -> String {
    #"{"v":1,"status":"live","revision":\#(revision),"preview":{"label":"localhost:5173","active":true},"entries":[{"id":"reply","role":"assistant","finished":true,"items":[{"type":"text","text":"\#(text)"}]}]}"#
  }
  var service: SessionFeedService {
    .init(watch: { _, receive in self.watched += 1; self.receive = receive; return { self.unwatched += 1 } },
      reconnect: { _ in self.reconnects += 1 }, cached: { _, _, _ in Self.envelope(0, "cached") })
  }
  func send(_ generation: Int, _ revision: Int, _ text: String) {
    receive?(.init(generation: generation, state: "live", sessionId: "session", session: Self.envelope(revision, text)))
  }
}
@main struct FeedCheck {
  @MainActor static func wait(_ test: () -> Bool) async throws {
    for _ in 0..<1000 {
      if test() { return }
      try await Task.sleep(for: .milliseconds(2))
    }
    preconditionFailure("Feed did not reach its expected state")
  }
  @MainActor static func main() async throws {
    let fixture = Fixture()
    let feed = SessionFeed(sessionId: "session", userId: "user", workspaceId: "workspace", service: fixture.service)
    feed.start(); feed.start()
    try await wait { feed.state.entriesJSON.contains("cached") }
    precondition(fixture.watched == 1 && feed.state.status == "syncing")
    fixture.send(1, 3, "live")
    try await wait { feed.state.status == "live" }
    precondition(feed.state.preview?.label == "localhost:5173")
    fixture.send(0, 100, "stale-generation")
    fixture.send(1, 2, "stale-revision")
    fixture.send(1, 4, "accepted")
    try await wait { feed.state.revision == 4 }
    precondition(feed.state.entriesJSON.contains("accepted"))
    fixture.send(2, 0, "new-runtime")
    try await wait { feed.generation == 2 }
    precondition(feed.state.entriesJSON.contains("new-runtime"))
    feed.reconnect(); precondition(fixture.reconnects == 1)
    fixture.send(2, 1, "after-close")
    feed.finish(); feed.finish(); feed.reconnect()
    try await Task.sleep(for: .milliseconds(50))
    precondition(fixture.unwatched == 1 && fixture.reconnects == 1 && !feed.watching)
    precondition(!feed.state.entriesJSON.contains("after-close"))
    print("PASS: cache before live, one subscription, generation/revision ordering, reconnect and cancellation")
  }
}
