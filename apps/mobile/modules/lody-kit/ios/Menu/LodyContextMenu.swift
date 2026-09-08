import ExpoModulesCore
import UIKit

@Record
struct LodyContextMenuAction {
  var id: String = ""
  var title: String = ""
  var symbol: String = ""
  var destructive: Bool = false
}

final class LodyContextMenu: ExpoView, UIContextMenuInteractionDelegate {
  let onAction = EventDispatcher()
  private var actions: [LodyContextMenuAction] = []

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    addInteraction(UIContextMenuInteraction(delegate: self))
  }

  func setActions(_ value: [LodyContextMenuAction]) {
    actions = value
  }

  func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
    guard !actions.isEmpty else { return nil }
    let items = actions
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
      UIMenu(children: items.map { action in
        UIAction(
          title: action.title,
          image: action.symbol.isEmpty ? nil : UIImage(systemName: action.symbol),
          attributes: action.destructive ? [.destructive] : []
        ) { _ in self?.onAction(["id": action.id]) }
      })
    }
  }
}
