import UIKit

@MainActor func descendants(_ view: UIView) -> [UIView] {
  [view] + view.subviews.flatMap(descendants)
}

let host = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
let composer = UIView(frame: .zero)
composer.translatesAutoresizingMaskIntoConstraints = false
let chrome = ChatInputChrome()
chrome.translatesAutoresizingMaskIntoConstraints = false
host.addSubview(composer)
host.addSubview(chrome)
NSLayoutConstraint.activate([
  composer.leadingAnchor.constraint(equalTo: host.leadingAnchor),
  composer.trailingAnchor.constraint(equalTo: host.trailingAnchor),
  composer.bottomAnchor.constraint(equalTo: host.bottomAnchor),
  composer.heightAnchor.constraint(equalToConstant: 64),
  chrome.centerXAnchor.constraint(equalTo: composer.centerXAnchor),
  chrome.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
  chrome.heightAnchor.constraint(equalToConstant: ChatInputChrome.controlSize),
])
let window = UIWindow(frame: host.bounds)
window.addSubview(host)
window.isHidden = false
host.layoutIfNeeded()

@MainActor func statusControl() -> UIButton {
  descendants(chrome).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "chat-connection-status" }!
}

@MainActor func scrollControl() -> UIButton {
  descendants(chrome).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "chat-scroll-to-bottom" }!
}

@MainActor func frame(_ view: UIView) -> CGRect {
  view.convert(view.bounds, to: host)
}

@MainActor func shown(_ view: UIView) -> Bool {
  var current: UIView? = view
  while let node = current {
    if node.isHidden { return false }
    current = node.superview
  }
  return true
}

@MainActor func show(_ status: ChatInputChrome.Status, scroll: Bool) {
  UIView.performWithoutAnimation {
    chrome.status = status
    chrome.scrollVisible = scroll
    host.layoutIfNeeded()
  }
}

show(.connecting, scroll: false)
precondition(!chrome.isHidden, "Connecting chrome must be visible")
precondition(!shown(scrollControl()), "Connecting alone must not show scroll-to-bottom")
let connecting = statusControl()
precondition(connecting.accessibilityLabel == LodyStrings.text("native.chat.connection.connecting"))
precondition(!connecting.accessibilityTraits.contains(.button), "Connecting is status, not an action")
precondition(abs(frame(connecting).midX - 195) < 1, "A single chrome item sits on the composer center")
precondition(abs(frame(connecting).height - ChatInputChrome.controlSize) < 0.5)
precondition(abs(frame(connecting).maxY + 8 - composer.frame.minY) < 0.6, "Chrome shares the current scroll-button baseline")

var reconnected = false
chrome.onReconnect = { reconnected = true }
connecting.sendActions(for: .touchUpInside)
precondition(!reconnected, "Connecting must not invoke reconnect")

show(.connecting, scroll: true)
let statusBoth = frame(statusControl())
let scrollBoth = frame(scrollControl())
precondition(shown(scrollControl()))
precondition(abs(scrollBoth.width - ChatInputChrome.scrollSize) < 0.5)
precondition(abs(scrollBoth.height - ChatInputChrome.scrollSize) < 0.5)
precondition(abs(scrollBoth.minX - statusBoth.maxX - ChatInputChrome.spacing) < 1,
  "Paired glasses keep a half-button gap")
precondition(abs(statusBoth.midY - scrollBoth.midY) < 0.5, "Paired glasses share one baseline")
precondition(abs((statusBoth.minX + scrollBoth.maxX) / 2 - 195) < 1,
  "Paired glasses stay centered as a group")
let outside = chrome.convert(CGPoint(x: scrollBoth.maxX + 8, y: scrollBoth.midY), from: host)
precondition(
  chrome.hitTest(outside, with: nil) === scrollControl(),
  "A 22-point scroll glass must still receive a 44-point hit"
)

let container = descendants(chrome).compactMap { $0 as? UIVisualEffectView }.first { $0.effect is UIGlassContainerEffect }!
precondition((container.effect as! UIGlassContainerEffect).spacing == ChatInputChrome.spacing)
let glasses = descendants(container).compactMap { $0 as? UIVisualEffectView }.filter { $0.effect is UIGlassEffect }
precondition(glasses.count == 2, "Status and scroll must be separate glass surfaces in one container")

show(.paused, scroll: true)
let paused = statusControl()
precondition(paused.accessibilityLabel == LodyStrings.text("native.chat.connection.paused"))
precondition(paused.accessibilityTraits.contains(.button))
paused.sendActions(for: .touchUpInside)
precondition(reconnected, "Paused chrome must reconnect")

show(.paused, scroll: false)
precondition(!shown(scrollControl()))
precondition(abs(frame(statusControl()).midX - 195) < 1, "Dropping scroll returns status to center")

show(.none, scroll: false)
precondition(chrome.isHidden, "Chrome must collapse when both states are gone")

show(.none, scroll: true)
precondition(!chrome.isHidden)
precondition(!shown(statusControl()))
precondition(abs(frame(scrollControl()).midX - 195) < 1, "Scroll alone occupies the original center")
print("Chat chrome: exclusive copy, centered single, paired 22-point gap, and collapse passed")
