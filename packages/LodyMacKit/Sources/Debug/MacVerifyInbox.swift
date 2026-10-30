#if DEBUG
import Foundation

@MainActor
final class MacVerifyInbox {
  struct Message: Equatable {
    let seq: String
    let routes: [MacVerifyRoute]
  }

  static let request = Notification.Name("app.innei.lody.mac.verify.open")
  static let done = Notification.Name("app.innei.lody.mac.verify.opened")

  private let route: @MainActor (MacVerifyRoute) -> Void
  private let acknowledge: @MainActor (String) -> Void
  private var observer: NSObjectProtocol?

  init(
    route: @escaping @MainActor (MacVerifyRoute) -> Void,
    acknowledge: @escaping @MainActor (String) -> Void = { seq in
      DistributedNotificationCenter.default().postNotificationName(done, object: seq, userInfo: nil, deliverImmediately: true)
    }
  ) {
    self.route = route
    self.acknowledge = acknowledge
  }

  static func parse(_ object: String) -> Message? {
    let parts = object.split(separator: " ").map(String.init)
    guard let seq = parts.first, Int(seq) != nil, parts.count > 1 else { return nil }
    let routes = parts.dropFirst().compactMap { URL(string: $0).flatMap(MacVerifyRoute.init) }
    guard routes.count == parts.count - 1 else { return nil }
    return Message(seq: seq, routes: routes)
  }

  func handle(_ object: String) {
    guard let message = Self.parse(object) else { return }
    message.routes.forEach(route)
    acknowledge(message.seq)
  }

  func listen() {
    // Sandboxed senders such as the XCUITest runner may only pass a string object, so the routes travel there.
    observer = DistributedNotificationCenter.default().addObserver(forName: Self.request, object: nil, queue: .main) { [weak self] note in
      let object = note.object as? String
      MainActor.assumeIsolated {
        if let object { self?.handle(object) }
      }
    }
  }

  func stop() {
    observer.map(DistributedNotificationCenter.default().removeObserver)
    observer = nil
  }
}
#endif
