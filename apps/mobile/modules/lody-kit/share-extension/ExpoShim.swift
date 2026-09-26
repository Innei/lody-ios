import UIKit

// The extension compiles LodyKit views by reference without linking Expo. These
// stand-ins keep their declarations valid; events reach the host through closures.
final class AppContext: Sendable {}

class ExpoView: UIView {
  weak var appContext: AppContext?

  required init(appContext: AppContext? = nil) {
    self.appContext = appContext
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }
}

final class EventDispatcher {
  func callAsFunction(_ payload: [String: Any] = [:]) {}
}

protocol Record {
  init()
}

@propertyWrapper
struct Field<Value> {
  var wrappedValue: Value
  init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
