import UIKit

struct ChatForkMenu: Equatable {
  var state: String
  var reason: String

  init(json: String) {
    let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    state = object?["state"] as? String ?? "hidden"
    reason = object?["reason"] as? String ?? ""
  }

  @MainActor
  func elements(finished: Bool, onFork: @escaping (String) -> Void) -> [UIMenuElement] {
    guard state != "hidden" else { return [] }
    let disabled = state != "enabled" || !finished
    let note = finished ? reason : LodyStrings.text("native.chat.message.fork.streaming")
    let items = [
      ("sideChat", "bubble.left.and.text.bubble.right"),
      ("tab", "square.on.square"),
      ("worktree", "arrow.triangle.branch"),
    ].map { target, symbol in
      let action = UIAction(
        title: LodyStrings.text("native.chat.message.fork." + target),
        image: UIImage(systemName: symbol),
        attributes: disabled ? .disabled : []
      ) { _ in onFork(target) }
      action.subtitle = disabled && !note.isEmpty
        ? note
        : LodyStrings.text("native.chat.message.fork." + target + "Subtitle")
      action.accessibilityIdentifier = "fork-" + target
      return action
    }
    return [UIMenu(options: .displayInline, children: items)]
  }
}
