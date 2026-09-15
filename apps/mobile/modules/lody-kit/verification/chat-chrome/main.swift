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
  chrome.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 16),
  chrome.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -16),
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
let lineHeight = connecting.titleLabel!.font.lineHeight
precondition(abs(frame(connecting).height - lineHeight - 12) < 1,
  "Status height \(frame(connecting).height) follows line \(lineHeight) with six-point vertical padding")
precondition(abs(frame(connecting).maxY + 8 - composer.frame.minY) < 0.6, "Chrome shares the current scroll-button baseline")

var reconnected = false
chrome.onReconnect = { reconnected = true }
connecting.sendActions(for: .touchUpInside)
precondition(!reconnected, "Connecting must not invoke reconnect")

show(.connecting, scroll: true)
let statusBoth = frame(statusControl())
let scrollBoth = frame(scrollControl())
precondition(shown(scrollControl()))
precondition(abs(scrollBoth.width - ChatInputChrome.controlSize) < 0.5)
precondition(abs(scrollBoth.height - ChatInputChrome.controlSize) < 0.5)
precondition(abs(scrollBoth.maxX - (composer.frame.maxX - 18)) < 0.5,
  "Scroll action shares the send control trailing inset")
precondition(abs(statusBoth.maxY - scrollBoth.maxY) < 0.5, "Paired glasses share one baseline")
let expectedSymbol = UIImage(
  systemName: "arrow.down",
  withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
)!
let actualSymbol = UIImage(
  systemName: "arrow.down",
  withConfiguration: scrollControl().configuration?.preferredSymbolConfigurationForImage
)!
precondition(abs(actualSymbol.size.width - expectedSymbol.size.width) < 0.5)
precondition(abs(actualSymbol.size.height - expectedSymbol.size.height) < 0.5)
precondition(abs(statusBoth.midX - 195) < 1,
  "Showing scroll must not move the connection status")
let inside = chrome.convert(CGPoint(x: scrollBoth.midX + 21, y: scrollBoth.midY), from: host)
precondition(
  chrome.hitTest(inside, with: nil) === scrollControl(),
  "Compact scroll glass retains a 44-point touch target"
)
let gap = chrome.convert(CGPoint(x: (statusBoth.maxX + scrollBoth.minX) / 2, y: scrollBoth.midY), from: host)
precondition(chrome.hitTest(gap, with: nil) == nil, "Empty chrome space passes touches to the transcript")
var scrolled = false
chrome.onScrollToBottom = { scrolled = true }
scrollControl().sendActions(for: .touchUpInside)
precondition(scrolled, "Scroll action reaches the transcript owner")

show(.paused, scroll: true)
let paused = statusControl()
precondition(paused.accessibilityLabel == LodyStrings.text("native.chat.connection.paused"))
precondition(paused.accessibilityTraits.contains(.button))
let pausedEdge = chrome.convert(CGPoint(x: frame(paused).midX, y: frame(paused).midY + 21), from: host)
precondition(chrome.hitTest(pausedEdge, with: nil) === paused,
  "Compact reconnect glass retains a 44-point touch target")
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
precondition(frame(scrollControl()) == scrollBoth, "Hiding status must not move the scroll action")
host.frame.size = CGSize(width: 760, height: 520)
host.layoutIfNeeded()
precondition(abs(frame(scrollControl()).maxX - (composer.frame.maxX - 18)) < 0.5)
precondition(abs(frame(scrollControl()).maxY + 8 - composer.frame.minY) < 0.5,
  "Resizing the host preserves the composer baseline")
print("Chat chrome: 44-point scroll action aligned with send, independent status, touch passthrough and resize passed")
