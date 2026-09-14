import ExpoModulesCore
import UIKit

@Record
struct LodyMenuItem {
  var id: String = ""
  var title: String = ""
  var symbol: String = ""
  var selected: Bool = false
}

@Record
struct LodyMenuAvatar {
  var text: String = ""
  var color: String = ""
  var image: String = ""
}

final class LodyMenuButton: ExpoView {
  let onSelect = EventDispatcher()
  let onSize = EventDispatcher()
  private let button = UIButton(type: .system)
  private var barItem: UIBarButtonItem?
  private var avatar = LodyMenuAvatar()
  private var photoURL: URL?
  private var photo: UIImage?
  private var label = ""
  private var header = false

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    button.changesSelectionAsPrimaryAction = false
    button.showsMenuAsPrimaryAction = true
    addSubview(button)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      detachBarItem()
      return
    }
    apply()
    guard header else { return }
    DispatchQueue.main.async { [weak self] in self?.apply() }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if !header {
      button.frame = bounds
    }
  }

  func setHeader(_ value: Bool) {
    guard header != value else { return }
    header = value
    apply()
  }

  func setAccessibilityName(_ value: String) {
    button.accessibilityLabel = value
  }

  func setAvatar(_ value: LodyMenuAvatar) {
    avatar = value
    let url = LodyListPhoto.url(value.image)
    photoURL = url
    photo = url.flatMap { source in
      LodyListPhoto.image(for: source, ready: { [weak self] image in
        guard let self, self.photoURL == source else { return }
        self.photo = image
        self.apply()
      })
    }
    apply()
  }

  func setLabel(_ value: String) {
    label = value
    apply()
  }

  func setItems(_ value: [LodyMenuItem]) {
    button.menu = UIMenu(
      options: .singleSelection,
      children: value.map { item in
        UIAction(
          title: item.title,
          image: item.symbol.isEmpty ? nil : UIImage(systemName: item.symbol),
          state: item.selected ? .on : .off
        ) { [weak self] _ in self?.onSelect(["id": item.id]) }
      }
    )
  }

  private func apply() {
    LodyMenuButtonStyle.apply(
      label: label,
      avatar: LodyMenuButtonStyle.avatarImage(
        text: avatar.text,
        fill: lodyTint(avatar.color) ?? .systemIndigo,
        photo: photo
      ),
      to: button
    )
    if header {
      attachBarItem()
      return
    }
    detachBarItem()
    if button.superview !== self {
      addSubview(button)
    }
    onSize(["width": LodyMenuButtonStyle.unconstrainedWidth(for: button)])
  }

  private func attachBarItem() {
    guard let item = hostingController()?.navigationItem else { return }
    button.removeFromSuperview()
    let bar = hostingController()?.navigationController?.navigationBar
    let barWidth = bar?.bounds.width ?? 0
    let limit = LodyMenuButtonStyle.headerLimit(
      barWidth: barWidth > 0 ? barWidth : (window?.bounds.width ?? 390),
      safeLeading: bar?.safeAreaInsets.left ?? 0,
      safeTrailing: bar?.safeAreaInsets.right ?? 0
    )
    button.bounds.size = LodyMenuButtonStyle.fittedSize(for: button, limit: limit)
    if barItem == nil {
      barItem = UIBarButtonItem(customView: button)
    }
    guard let barItem else { return }
    var items = item.leftBarButtonItems ?? []
    items.removeAll { $0 === barItem }
    items.insert(barItem, at: 0)
    item.leftBarButtonItems = items
  }

  private func detachBarItem() {
    guard let barItem else { return }
    if let item = hostingController()?.navigationItem {
      item.leftBarButtonItems = item.leftBarButtonItems?.filter { $0 !== barItem }
    }
    self.barItem = nil
  }

  private func hostingController() -> UIViewController? {
    var responder: UIResponder? = self
    while let current = responder {
      if let controller = current as? UIViewController {
        return controller
      }
      responder = current.next
    }
    return nil
  }
}
