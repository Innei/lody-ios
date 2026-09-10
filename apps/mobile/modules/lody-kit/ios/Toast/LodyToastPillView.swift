import UIKit

final class LodyToastPillView: UIView {
  let message: String
  private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
  private let glyph = UIImageView()
  private let label = UILabel()
  private let drawsCheckmark: Bool
  private var playedGlyph = false

  var showsContent = true {
    didSet {
      label.isHidden = !showsContent
      glyph.isHidden = !showsContent
      isAccessibilityElement = showsContent
      accessibilityElementsHidden = !showsContent
    }
  }

  init(message: String, symbol: String, tint: UIColor) {
    self.message = message
    drawsCheckmark = symbol == "checkmark"
    super.init(frame: .zero)
    layer.cornerCurve = .continuous
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.08
    layer.shadowRadius = 12
    layer.shadowOffset = CGSize(width: 0, height: 4)
    blur.clipsToBounds = true
    blur.layer.cornerCurve = .continuous
    addSubview(blur)

    label.text = message
    label.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
      for: .systemFont(ofSize: 15, weight: .medium)
    )
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .label
    label.numberOfLines = 0
    blur.contentView.addSubview(label)

    glyph.image = UIImage(systemName: symbol)?
      .withConfiguration(UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
    glyph.tintColor = tint
    glyph.contentMode = .center
    blur.contentView.addSubview(glyph)

    isAccessibilityElement = true
    accessibilityIdentifier = "lody.toast"
    accessibilityLabel = message
    accessibilityTraits = .staticText
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil, drawsCheckmark, !playedGlyph else { return }
    playedGlyph = true
    glyph.playDrawOnSymbol()
  }

  func fittedSize(maxWidth: CGFloat) -> CGSize {
    let text = label.sizeThatFits(
      CGSize(width: max(1, maxWidth - 64), height: .greatestFiniteMagnitude)
    )
    return CGSize(
      width: min(maxWidth, ceil(text.width) + 64),
      height: max(48, ceil(text.height) + 24)
    )
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let radius = min(24, bounds.height / 2)
    layer.cornerRadius = radius
    layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
    blur.frame = bounds
    blur.layer.cornerRadius = radius
    glyph.frame = CGRect(x: 18, y: (bounds.height - 18) / 2, width: 18, height: 18)
    label.frame = CGRect(x: 46, y: 12, width: max(0, bounds.width - 64), height: bounds.height - 24)
  }
}
