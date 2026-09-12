import UIKit

/// Both list hosts render the same declared actions; the caller owns navigation.
@MainActor
enum LodyListRowInteractions {
  static func swipes(
    row: LodyListRow,
    leading: Bool,
    perform: @escaping (String, String) -> Void
  ) -> UISwipeActionsConfiguration? {
    let actions = leading ? row.leadingActions : row.actions
    guard !actions.isEmpty else { return nil }
    return UISwipeActionsConfiguration(actions: actions.map { action in
      let item = UIContextualAction(style: action.destructive ? .destructive : .normal, title: action.title) { _, _, done in
        perform(row.id, action.id)
        done(true)
      }
      item.image = action.symbol.isEmpty ? nil : UIImage(systemName: action.symbol)
      if let tint = lodyTint(action.tint) { item.backgroundColor = tint }
      return item
    })
  }

  static func menu(
    row: LodyListRow,
    userId: String,
    workspaceId: String,
    perform: @escaping (String, String) -> Void
  ) -> UIContextMenuConfiguration? {
    guard !row.menuActions.isEmpty else { return nil }
    return UIContextMenuConfiguration(identifier: row.id as NSString, previewProvider: {
      guard row.preview == "session" else { return nil }
      return ChatTranscriptPreviewController(sessionId: row.id, title: row.title, userId: userId, workspaceId: workspaceId)
    }, actionProvider: { _ in
      UIMenu(children: row.menuActions.map { action in
        UIAction(title: action.title,
                 image: action.symbol.isEmpty ? nil : UIImage(systemName: action.symbol),
                 attributes: action.destructive ? [.destructive] : []) { _ in
          if action.id == "copyPath" {
            UIPasteboard.general.string = row.subtitle
          } else {
            perform(row.id, action.id)
          }
        }
      })
    })
  }
}
