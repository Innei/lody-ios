import UIKit

@MainActor
enum LodyMenuButtonStyle {
  static let avatarSide: CGFloat = 28
  static let trailingInset: CGFloat = 10

  static func apply(_ value: UIButton.Configuration, to button: UIButton) {
    var configuration = value
    configuration.titleLineBreakMode = .byTruncatingTail
    button.configuration = configuration
    button.titleLabel?.numberOfLines = 1
    button.titleLabel?.lineBreakMode = .byTruncatingTail
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
