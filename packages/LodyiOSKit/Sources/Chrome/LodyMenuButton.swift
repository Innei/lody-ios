import UIKit

struct LodyMenuItem {
  var id: String = ""
  var title: String = ""
  var symbol: String = ""
  var selected: Bool?
  var subtitle: String = ""
  var disabled: Bool = false
  var children: [LodyMenuItem] = []
}

struct LodyMenuAvatar {
  var text: String = ""
  var color: String = ""
  var image: String = ""
}

final class LodyMenuButton: UIView {
  var onSelect: ([String: Any]) -> Void = { _ in }
  var onSize: ([String: Any]) -> Void = { _ in }
  var selected: ((String) -> Void)?
  var sized: ((CGFloat) -> Void)?
  private let button = UIButton(type: .system)
  private var avatar = LodyMenuAvatar()
  private var photoURL: URL?
  private var photo: UIImage?
  private var label = ""
  private var detail = ""

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override init(frame: CGRect) {
    super.init(frame: frame)
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

  func setDetail(_ value: String) {
    detail = value
    apply()
  }

  func setItems(_ value: [LodyMenuItem]) {
    func action(_ item: LodyMenuItem, state: UIMenuElement.State = .off) -> UIAction {
      let result = UIAction(
        title: item.title,
        image: item.symbol.isEmpty ? nil : UIImage(systemName: item.symbol),
        attributes: item.disabled ? .disabled : [],
        state: state
      ) { [weak self] _ in
        self?.onSelect(["id": item.id])
        self?.selected?(item.id)
      }
      result.subtitle = item.subtitle.isEmpty ? nil : item.subtitle
      return result
    }

    func element(_ item: LodyMenuItem) -> UIMenuElement {
      if item.children.isEmpty { return action(item) }
      return UIMenu(title: item.title, subtitle: item.subtitle.isEmpty ? nil : item.subtitle,
        image: item.symbol.isEmpty ? nil : UIImage(systemName: item.symbol), children: item.children.map(element))
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
      item.selected == nil ? element(item) : nil
    }
    if !actions.isEmpty {
      children.append(UIMenu(options: .displayInline, children: actions))
    }
    button.menu = UIMenu(children: children)
  }

  private func apply() {
    let tint = lodyTint(avatar.color)
    LodyMenuButtonStyle.apply(
      label: label,
      detail: detail,
      avatar: LodyMenuButtonStyle.avatarImage(
        text: avatar.text,
        fill: tint ?? .lodyAccent,
        foreground: tint == nil ? LodyAccentChoice.current.foregroundColor : .white,
        photo: photo
      ),
      to: button
    )
    let width = LodyMenuButtonStyle.unconstrainedWidth(for: button)
    onSize(["width": width])
    sized?(width)
  }
}
