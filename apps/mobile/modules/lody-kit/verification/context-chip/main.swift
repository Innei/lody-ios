import UIKit

@MainActor func descendants(_ view: UIView) -> [UIView] {
  [view] + view.subviews.flatMap(descendants)
}

let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
window.isHidden = false

// A newly attached conversation must already have its Simulator chip and replies
// in their final positions while the navigation controller slides the page in.
let openingStrip = ChatQuickRepliesView(frame: CGRect(x: 0, y: 500, width: 390, height: ChatQuickRepliesView.chipHeight))
window.addSubview(openingStrip)
openingStrip.layoutIfNeeded()
let openingReplies = [ChatQuickReply(id: "continue", label: "Continue", message: "Continue")]
let openingContext = ChatPreviewChip(label: "iOS Simulator", symbol: "iphone", state: "ready", accessibilityLabel: "Open Simulator")
openingStrip.render(openingReplies, context: openingContext, showsReplies: true, compact: false, visible: true, animated: true)
openingStrip.layoutIfNeeded()
CATransaction.flush()
let openingButtons = descendants(openingStrip).compactMap { $0 as? UIButton }.filter {
  $0.accessibilityIdentifier == "session-preview" || $0.accessibilityIdentifier == "quick-reply:continue"
}
precondition(openingButtons.count == 2)
for tick in 0..<30 {
  RunLoop.main.run(until: Date().addingTimeInterval(0.02))
  if tick % 3 == 0 {
    openingStrip.render(openingReplies, context: openingContext, showsReplies: true, compact: false, visible: true, animated: true)
    openingStrip.layoutIfNeeded()
  }
  for button in openingButtons {
    let displayed = button.layer.presentation()?.frame ?? button.frame
    precondition(abs(displayed.minX - button.frame.minX) < 1 && abs(displayed.width - button.bounds.width) < 1,
      "Initial Simulator chip/replies must not run a second entrance or restart on unchanged state: \(button.accessibilityIdentifier ?? "") \(displayed) vs \(button.frame)")
  }
}
openingStrip.removeFromSuperview()
print("Context chip: initial conversation layout and repeated identical updates stay still")

let navigationWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
let navigation = UINavigationController(rootViewController: UIViewController())
navigationWindow.rootViewController = navigation
navigationWindow.makeKeyAndVisible()
RunLoop.main.run(until: Date().addingTimeInterval(0.1))
let destination = UIViewController()
destination.view.addSubview(openingStrip)
openingStrip.render([], context: openingContext, showsReplies: true, compact: false, visible: true, animated: false)
navigation.pushViewController(destination, animated: true)
RunLoop.main.run(until: Date().addingTimeInterval(0.04))
precondition(destination.transitionCoordinator != nil, "The delayed replies regression requires an actual navigation transition")
openingStrip.render(openingReplies, context: openingContext, showsReplies: true, compact: false, visible: true, animated: true)
openingStrip.layoutIfNeeded()
CATransaction.flush()
let delayedReply = descendants(openingStrip).first { $0.accessibilityIdentifier == "quick-reply:continue" }!
for _ in 0..<25 {
  RunLoop.main.run(until: Date().addingTimeInterval(0.02))
  let displayed = delayedReply.layer.presentation()?.frame ?? delayedReply.frame
  precondition(abs(displayed.minX - delayedReply.frame.minX) < 1 && abs(displayed.width - delayedReply.bounds.width) < 1,
    "Replies arriving during navigation must move with the page, without a second slide/expansion: \(displayed) vs \(delayedReply.frame)")
}
navigationWindow.isHidden = true
print("Context chip: delayed replies during a navigation push move with the page")
