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
}

final class LodyMenuButton: ExpoView {
  let onSelect = EventDispatcher()
  let onSize = EventDispatcher()
  private let button = UIButton(type: .system)
  private var avatar = LodyMenuAvatar()
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

  private func avatarImage() -> UIImage {
    let side: CGFloat = 28
    let fill = lodyTint(avatar.color) ?? .systemIndigo
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
      fill.setFill()
      context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: side, height: side))
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: UIColor.white,
      ]
      let text = NSAttributedString(string: avatar.text, attributes: attributes)
      let size = text.size()
      text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
    }.withRenderingMode(.alwaysOriginal)
  }

  private func apply() {
    var config = UIButton.Configuration.plain()
    config.image = avatarImage()
    config.imagePadding = 8
    config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 4)
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
