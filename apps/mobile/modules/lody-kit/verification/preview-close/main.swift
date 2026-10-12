import UIKit

@MainActor func descendants(_ view: UIView) -> [UIView] {
  [view] + view.subviews.flatMap(descendants)
}

let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
window.isHidden = false
let strip = ChatQuickRepliesView(frame: CGRect(x: 0, y: 500, width: 390, height: ChatQuickRepliesView.chipHeight))
window.addSubview(strip)
let replies = [ChatQuickReply(id: "continue", label: "Continue", message: "Continue")]
var events: [String] = []
strip.onPreview = { events.append($0) }

@MainActor func context(_ state: String = "ready", id: String = "stop", title: String = "Stop Sharing") -> ChatPreviewChip {
  ChatPreviewChip(label: "localhost:52920", symbol: "safari", state: state,
                  accessibilityLabel: "Open preview localhost:52920", actions: [
                    .init(id: "copy", title: "Copy Share Link", symbol: "link"),
                    .init(id: id, title: title, symbol: "xmark", destructive: true, close: true),
                  ])
}

@MainActor func render(_ chip: ChatPreviewChip?, compact: Bool = false, items: [ChatQuickReply]? = nil) {
  strip.render(items ?? replies, context: chip, showsReplies: !compact, compact: compact, visible: true)
  strip.layoutIfNeeded()
  CATransaction.flush()
}

render(context())
let close = descendants(strip).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-preview-close" }!
let open = descendants(strip).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-preview" }!
let closeFrame = close.convert(close.bounds, to: strip)
precondition(!close.isHidden && close.bounds.width >= 44 && close.accessibilityLabel == "Stop Sharing")
precondition(closeFrame.minX >= open.convert(open.bounds, to: strip).maxX,
  "Opening and closing preview must have separate controls")
precondition(strip.hitTest(CGPoint(x: closeFrame.midX, y: closeFrame.minY + 43), with: nil) === close,
  "Close must accept a 44 pt vertical touch target beyond its visible capsule")
close.sendActions(for: .touchUpInside)
precondition(events == ["stop"], "Close must revoke without opening the preview")
open.sendActions(for: .touchUpInside)
precondition(events == ["stop", "open"], "The address must retain ordinary opening")

render(context("stopping"))
precondition(!close.isEnabled && !open.isEnabled && close.configuration?.showsActivityIndicator == true,
  "An in-flight revoke must show progress and disable both actions")
close.sendActions(for: .touchUpInside)
open.sendActions(for: .touchUpInside)
precondition(events == ["stop", "open"], "Stopping must ignore programmatic close and open actions")
render(context("connecting"))
precondition(!close.isEnabled && !open.isEnabled, "Create and stop cannot overlap")
close.sendActions(for: .touchUpInside)
open.sendActions(for: .touchUpInside)
precondition(events == ["stop", "open"], "Connecting must ignore programmatic close and open actions")
render(context(), compact: true)
precondition(!close.isHidden && close.isEnabled && abs(open.bounds.width - ChatQuickRepliesView.chipHeight) < 0.5,
  "Typing must keep the close control next to the compact preview icon")

render(context(id: "0:stop"), items: [])
precondition(close.superview != nil && !close.isHidden,
  "Replacing suggestions must not retire the close control")
close.sendActions(for: .touchUpInside)
precondition(events.last == "0:stop", "Combined resource actions must keep their routing prefix")
render(context(id: "dismiss", title: "Hide Preview"))
precondition(close.accessibilityLabel == "Hide Preview")
close.sendActions(for: .touchUpInside)
precondition(events.last == "dismiss", "An unshared address must hide without revoking a tunnel")
render(ChatPreviewChip(label: "iPhone 17", symbol: "iphone", state: "ready", accessibilityLabel: "Open Simulator"))
precondition(close.isHidden && !open.isHidden, "Resources without close actions must not gain an unrelated action")
render(nil)
precondition(close.isHidden && open.isHidden, "A hidden preview must remove both controls")
print("Preview close: separate open/close, 44 pt touch, busy gating, compact typing, stable suggestions and resource action routing passed")
