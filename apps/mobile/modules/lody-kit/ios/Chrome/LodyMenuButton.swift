import ExpoModulesCore
import UIKit

@Record
struct LodyMenuItem {
  var id: String = ""
  var title: String = ""
  var symbol: String = ""
  var selected: Bool?
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
  private var avatar = LodyMenuAvatar()
  private var photoURL: URL?
  private var photo: UIImage?
  private var label = ""

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    button.changesSelectionAsPrimaryAction = false
    button.showsMenuAsPrimaryAction = true
    addSubview(button)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    apply()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    button.frame = bounds
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
    func action(_ item: LodyMenuItem, state: UIMenuElement.State = .off) -> UIAction {
      UIAction(
        title: item.title,
        image: item.symbol.isEmpty ? nil : UIImage(systemName: item.symbol),
        state: state
      ) { [weak self] _ in self?.onSelect(["id": item.id]) }
    }

    let choices = value.compactMap { item -> UIAction? in
      guard let selected = item.selected else { return nil }
      return action(item, state: selected ? .on : .off)
    }
    var children: [UIMenuElement] = []
    if !choices.isEmpty {
      children.append(UIMenu(options: [.displayInline, .singleSelection], children: choices))
    }
    let actions = value.compactMap { item in
      item.selected == nil ? action(item) : nil
    }
    if !actions.isEmpty {
      children.append(UIMenu(options: .displayInline, children: actions))
    }
    button.menu = UIMenu(children: children)
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
    onSize(["width": LodyMenuButtonStyle.unconstrainedWidth(for: button)])
  }
}
