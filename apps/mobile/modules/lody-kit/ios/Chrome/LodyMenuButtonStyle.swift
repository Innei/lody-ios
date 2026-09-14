import UIKit

@MainActor
enum LodyMenuButtonStyle {
  static let avatarSide: CGFloat = 28
  static let imagePadding: CGFloat = 8
  static let leadingInset: CGFloat = 2
  static let trailingInset: CGFloat = 10
  static let height: CGFloat = 44
  static let rightItemsReserve: CGFloat = 120

  static func apply(_ value: UIButton.Configuration, to button: UIButton) {
    var configuration = value
    configuration.titleLineBreakMode = .byTruncatingTail
    button.configuration = configuration
    button.titleLabel?.numberOfLines = 1
    button.titleLabel?.lineBreakMode = .byTruncatingTail
  }

  static func apply(label: String, avatar: UIImage, to button: UIButton) {
    var configuration = UIButton.Configuration.plain()
    configuration.image = avatar
    configuration.imagePadding = imagePadding
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 4, leading: leadingInset, bottom: 4, trailing: trailingInset
    )
    configuration.attributedTitle = AttributedString(
      label,
      attributes: AttributeContainer([
        .font: UIFont.preferredFont(forTextStyle: .headline),
        .foregroundColor: UIColor.label,
      ])
    )
    apply(configuration, to: button)
  }

  static func unconstrainedWidth(for button: UIButton) -> CGFloat {
    button.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: height)).width
  }

  static func headerLimit(barWidth: CGFloat, safeLeading: CGFloat, safeTrailing: CGFloat) -> CGFloat {
    max(height, barWidth - safeLeading - safeTrailing - rightItemsReserve)
  }

  static func fittedSize(for button: UIButton, limit: CGFloat) -> CGSize {
    let width = min(max(unconstrainedWidth(for: button), height), limit)
    return CGSize(width: width, height: height)
  }

  static func avatarImage(text: String, fill: UIColor, photo: UIImage?) -> UIImage {
    let side = avatarSide
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
      let bounds = CGRect(x: 0, y: 0, width: side, height: side)
      UIBezierPath(ovalIn: bounds).addClip()
      if let photo {
        photo.draw(in: bounds)
        return
      }
      fill.setFill()
      context.cgContext.fillEllipse(in: bounds)
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: UIColor.white,
      ]
      let glyph = NSAttributedString(string: text, attributes: attributes)
      let size = glyph.size()
      glyph.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
    }.withRenderingMode(.alwaysOriginal)
  }
}
