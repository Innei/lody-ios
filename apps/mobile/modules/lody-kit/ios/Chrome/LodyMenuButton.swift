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
    var config = UIButton.Configuration.plain()
    config.image = LodyMenuButtonStyle.avatarImage(
      text: avatar.text,
      fill: lodyTint(avatar.color) ?? .systemIndigo,
      photo: photo
    )
    config.imagePadding = 8
    config.contentInsets = NSDirectionalEdgeInsets(
      top: 4, leading: 2, bottom: 4, trailing: LodyMenuButtonStyle.trailingInset
    )
    config.attributedTitle = AttributedString(
      label,
      attributes: AttributeContainer([
        .font: UIFont.preferredFont(forTextStyle: .headline),
        .foregroundColor: UIColor.label,
      ])
    )
    LodyMenuButtonStyle.apply(config, to: button)
    onSize(["width": min(button.intrinsicContentSize.width, 200)])
  }
}
