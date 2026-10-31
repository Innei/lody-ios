import UIKit

enum LodyPresenceMark: Equatable {
  case none
  case dot(online: Bool)
  case segments(online: Int, total: Int)
  case share(online: Int, total: Int)

  static let segmentLimit = 6

  init(online: Int, total: Int, known: Bool) {
    switch total {
    case _ where !known || total <= 0: self = .none
    case 1: self = .dot(online: online > 0)
    case ...Self.segmentLimit: self = .segments(online: online, total: total)
    default: self = .share(online: online, total: total)
    }
  }
}

@MainActor
enum LodyMenuButtonStyle {
  static let avatarSide: CGFloat = 32
  static let imagePadding: CGFloat = 8
  static let leadingInset: CGFloat = 2
  static let trailingInset: CGFloat = 10
  static let height: CGFloat = 44

  static func apply(_ value: UIButton.Configuration, to button: UIButton) {
    var configuration = value
    configuration.titleLineBreakMode = .byTruncatingTail
    configuration.subtitleLineBreakMode = .byTruncatingTail
    button.configuration = configuration
    button.titleLabel?.numberOfLines = 1
    button.titleLabel?.lineBreakMode = .byTruncatingTail
    button.subtitleLabel?.numberOfLines = 1
  }

  static func apply(label: String, avatar: UIImage, to button: UIButton) {
    var configuration = UIButton.Configuration.plain()
    configuration.image = avatar
    configuration.imagePadding = imagePadding + 2
    configuration.titleAlignment = .leading
    configuration.titlePadding = 1
    configuration.contentInsets = NSDirectionalEdgeInsets(
      top: 2, leading: leadingInset, bottom: 2, trailing: trailingInset
    )
    let name = LodyDesign.font(.headline, size: 17, weight: .semibold)
    configuration.attributedTitle = AttributedString(
      label, attributes: AttributeContainer([.font: name, .foregroundColor: UIColor.lodyInk])
    )
    apply(configuration, to: button)
  }

  static func unconstrainedWidth(for button: UIButton) -> CGFloat {
    button.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: height)).width
  }

  static func avatarImage(
    text: String, fill: UIColor, foreground: UIColor = .white, photo: UIImage?, presence: LodyPresenceMark = .none
  ) -> UIImage {
    let side = avatarSide
    return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { renderer in
      let context = renderer.cgContext
      let bounds = CGRect(x: 0, y: 0, width: side, height: side)
      var ringed = false
      if case .segments = presence { ringed = true }
      if case .share = presence { ringed = true }
      let face = ringed ? bounds.insetBy(dx: 4, dy: 4) : bounds
      context.saveGState()
      let circle = UIBezierPath(ovalIn: face)
      circle.addClip()
      if let photo {
        photo.draw(in: face)
      } else {
        fill.setFill()
        circle.fill()
        let attributes: [NSAttributedString.Key: Any] = [
          .font: UIFont.systemFont(ofSize: ringed ? 11 : 13, weight: .bold),
          .foregroundColor: foreground,
        ]
        let glyph = NSAttributedString(string: text, attributes: attributes)
        let size = glyph.size()
        glyph.draw(at: CGPoint(x: face.midX - size.width / 2, y: face.midY - size.height / 2))
      }
      context.restoreGState()
      drawPresence(presence, in: bounds, context: context)
    }.withRenderingMode(.alwaysOriginal)
  }

  private static func drawPresence(_ presence: LodyPresenceMark, in bounds: CGRect, context: CGContext) {
    let center = CGPoint(x: bounds.midX, y: bounds.midY)
    let radius = bounds.width / 2 - 1.25
    let start = -CGFloat.pi / 2
    func arc(_ from: CGFloat, _ to: CGFloat, _ color: UIColor) {
      let path = UIBezierPath(arcCenter: center, radius: radius, startAngle: from, endAngle: to, clockwise: true)
      path.lineWidth = 2.2
      path.lineCapStyle = .round
      color.setStroke()
      path.stroke()
    }
    switch presence {
    case .none:
      return
    case .dot(let online):
      let dot = CGRect(x: bounds.maxX - 11, y: bounds.maxY - 11, width: 11, height: 11)
      context.setBlendMode(.clear)
      context.fillEllipse(in: dot.insetBy(dx: -2, dy: -2))
      context.setBlendMode(.normal)
      if online {
        UIColor.systemGreen.setFill()
        context.fillEllipse(in: dot)
      } else {
        let ring = UIBezierPath(ovalIn: dot.insetBy(dx: 0.9, dy: 0.9))
        ring.lineWidth = 1.6
        UIColor.lodyRail.setStroke()
        ring.stroke()
      }
    case .segments(let online, let total):
      let step = 2 * CGFloat.pi / CGFloat(total)
      let gap: CGFloat = 0.38
      for index in 0..<total {
        let from = start + CGFloat(index) * step + gap / 2
        arc(from, from + step - gap, index < online ? .lodySignal : .lodyRail)
      }
    case .share(let online, let total):
      arc(0, 2 * .pi, .lodyRail)
      guard online > 0 else { return }
      arc(start, start + 2 * .pi * CGFloat(min(online, total)) / CGFloat(total), .lodySignal)
    }
  }
}
