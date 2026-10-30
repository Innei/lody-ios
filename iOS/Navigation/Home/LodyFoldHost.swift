import UIKit

@MainActor
final class LodyFoldHost {
  let controller: UIViewController
  private let place: (UIViewController?, UIViewController?) -> Void

  // The arrangement API ships in the iOS 27.1 SDK (Swift 6.4); older
  // toolchains still build the app and keep the plain split everywhere.
  static func make(onLayout: @escaping () -> Void) -> LodyFoldHost? {
    #if compiler(>=6.4)
    guard #available(iOS 27.1, *) else { return nil }
    let arrangement = ArrangementController()
    arrangement.onLayout = onLayout
    arrangement.view.backgroundColor = .lodyBackground
    arrangement.updateArrangement(.split)
    return LodyFoldHost(controller: arrangement) { leading, trailing in
      arrangement.setViewController(leading, for: .primary)
      arrangement.setViewController(trailing, for: .secondary)
    }
    #else
    return nil
    #endif
  }

  static func observeHinge(on view: UIView, onChange: @escaping (Bool) -> Void) {
    #if compiler(>=6.4)
    guard #available(iOS 27.1, *) else { return }
    view.addInteraction(UIHingeInteraction { _, update in
      onChange(update.hinge?.status == .partiallyOpen)
    })
    #endif
  }

  private init(controller: UIViewController, place: @escaping (UIViewController?, UIViewController?) -> Void) {
    self.controller = controller
    self.place = place
  }

  func show(leading: UIViewController?, trailing: UIViewController?) {
    place(leading, trailing)
  }
}
