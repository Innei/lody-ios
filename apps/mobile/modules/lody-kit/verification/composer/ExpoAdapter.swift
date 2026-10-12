import UIKit

// Standalone verification observes Expo's public event boundary without an RN host.
public final class AppContext: Sendable {}
open class ExpoView: UIView {
  public weak var appContext: AppContext?
  public required init(appContext: AppContext? = nil) {
    self.appContext = appContext
    super.init(frame: .zero)
  }
  @available(*, unavailable)
  public required init?(coder: NSCoder) { fatalError() }
}
public final class EventDispatcher {
  public var onEventSent: (([String: Any]) -> Void)?
  public init() {}
  public func callAsFunction(_ payload: [String: Any]) { onEventSent?(payload) }
}
