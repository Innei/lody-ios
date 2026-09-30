import AVFoundation
import UIKit

/// The device body is drawn instead of using baguette's bezel image, which is
/// served only at 1x and blurs on a 3x screen. Button geometry comes from the
/// device definition, in viewport units.
@MainActor final class SimulatorDeviceView: UIView {
  final class DisplayView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
  }

  let definition: SimulatorDefinition
  let display = DisplayView()
  let seed = UIImageView()
  private let body = UIView()
  var bodyFrame: CGRect { body.frame }
  var bodyCornerRadius: CGFloat { body.layer.cornerRadius }
  private var buttons: [(UIButton, SimulatorDefinition.Button)] = []
  var onButton: (([String: String]) -> Void)?

  var canvasSize: CGSize {
    CGSize(width: definition.viewport.width + definition.margins.left + definition.margins.right,
           height: definition.viewport.height + definition.margins.top + definition.margins.bottom)
  }

  init(definition: SimulatorDefinition) {
    self.definition = definition
    super.init(frame: .zero)
    for item in definition.buttons {
      let button = UIButton(type: .custom)
      button.backgroundColor = UIColor(white: 0.17, alpha: 1)
      button.layer.cornerCurve = .continuous
      button.accessibilityLabel = Self.label(item.id)
      button.accessibilityIdentifier = "simulator-button:\(item.id)"
      button.addAction(UIAction { [weak self] _ in self?.press(button, item, down: true) }, for: .touchDown)
      button.addAction(UIAction { [weak self] _ in self?.press(button, item, down: false) }, for: [.touchUpOutside, .touchCancel])
      button.addAction(UIAction { [weak self] _ in
        self?.press(button, item, down: false)
        self?.onButton?(item.envelope)
      }, for: .touchUpInside)
      addSubview(button)
      buttons.append((button, item))
    }
    body.backgroundColor = UIColor(white: 0.02, alpha: 1)
    body.layer.borderColor = UIColor(white: 0.23, alpha: 1).cgColor
    body.layer.cornerCurve = .continuous
    body.layer.shadowColor = UIColor.black.cgColor
    body.layer.shadowOpacity = 0.18
    body.layer.shadowOffset = CGSize(width: 0, height: 12)
    body.isUserInteractionEnabled = false
    addSubview(body)
    for item in [seed, display] {
      item.clipsToBounds = true
      item.layer.cornerCurve = .continuous
      item.isUserInteractionEnabled = false
      addSubview(item)
    }
    seed.contentMode = .scaleAspectFill
    display.displayLayer.videoGravity = .resizeAspectFill
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    let scale = bounds.width / max(canvasSize.width, 1)
    let origin = CGPoint(x: definition.margins.left, y: definition.margins.top)
    func scaled(_ rect: CGRect) -> CGRect {
      CGRect(x: (origin.x + rect.minX) * scale, y: (origin.y + rect.minY) * scale,
             width: rect.width * scale, height: rect.height * scale)
    }
    body.frame = scaled(CGRect(origin: .zero, size: definition.viewport))
    body.layer.cornerRadius = (definition.cornerRadius + definition.screen.minX) * scale
    body.layer.borderWidth = 4 * scale
    body.layer.shadowRadius = 24 * scale
    body.layer.shadowPath = UIBezierPath(roundedRect: body.bounds, cornerRadius: body.layer.cornerRadius).cgPath
    for item in [seed, display] as [UIView] {
      item.frame = scaled(definition.screen)
      item.layer.cornerRadius = definition.cornerRadius * scale
    }
    for (button, item) in buttons {
      button.bounds.size = CGSize(width: item.box.width * scale, height: item.box.height * scale)
      button.center = CGPoint(x: scaled(item.box).midX, y: scaled(item.box).midY)
      button.layer.cornerRadius = 3 * scale
    }
  }

  private func press(_ button: UIButton, _ item: SimulatorDefinition.Button, down: Bool) {
    let inward: CGFloat = item.box.midX < definition.viewport.width / 2 ? 1 : -1
    let offset = button.bounds.width * 0.3125 * inward
    UIView.animate(withDuration: 0.12) {
      button.transform = down ? CGAffineTransform(translationX: offset, y: 0) : .identity
    }
  }

  private static func label(_ id: String) -> String {
    let key = "native.simulator.button.\(id)"
    let text = LodyStrings.text(key)
    return text == key ? id : text
  }
}
