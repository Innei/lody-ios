import CoreImage.CIFilterBuiltins
import UIKit

/// Retains one stream for its chat; full-screen navigation temporarily borrows it.
@MainActor final class SimulatorPreview: UIView {
  private var stream: SimulatorStreamView?
  private static let imageContext = CIContext(options: [.cacheIntermediates: false])
  private static let backdropOutset: CGFloat = 56
  private let backdrop = UIImageView()
  private var blurMask: CIImage?
  private var blurCornerRadius: CGFloat = 12
  private var refreshTimer: Timer?
  private let content = UIView()
  private let expand = UIButton(type: .system)
  private let close = UIButton(type: .system)
  private let entranceBlur = UIVisualEffectView()
  private var entranceTimer: Timer?
  private var needsEntrance = false
  private var area = CGRect.zero
  private var position = CGPoint(x: 1, y: 0)
  private var dragStart = CGPoint.zero
  var onAction: ((String) -> Void)?

  override var isHidden: Bool {
    didSet {
      guard oldValue != isHidden else { return }
      if isHidden { finishEntrance() } else { needsEntrance = true; setNeedsLayout() }
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backdrop.isUserInteractionEnabled = false
    backdrop.accessibilityIdentifier = "simulator-preview-blur"
    addSubview(backdrop)
    content.clipsToBounds = true
    content.layer.cornerRadius = 12
    content.layer.cornerCurve = .continuous
    addSubview(content)
    for (button, symbol, key, id, action) in [
      (expand, "arrow.up.left.and.arrow.down.right", "native.simulator.expand", "simulator-preview-expand", "expand"),
      (close, "xmark", "native.simulator.close", "simulator-preview-close", "close"),
    ] {
      button.setImage(UIImage(systemName: symbol), for: .normal)
      button.setPreferredSymbolConfiguration(.init(pointSize: 12, weight: .medium), forImageIn: .normal)
      button.adjustsImageSizeForAccessibilityContentSizeCategory = true
      button.imageView?.clipsToBounds = false
      button.imageView?.layer.shadowOpacity = 1
      button.imageView?.layer.shadowRadius = 3
      button.imageView?.layer.shadowOffset = .zero
      button.tintColor = .label
      button.accessibilityLabel = LodyStrings.text(key)
      button.accessibilityIdentifier = id
      button.addAction(UIAction { [weak self] _ in self?.onAction?(action) }, for: .touchUpInside)
      addSubview(button)
    }
    entranceBlur.isUserInteractionEnabled = false
    entranceBlur.isHidden = true
    entranceBlur.clipsToBounds = true
    entranceBlur.layer.cornerRadius = 12
    addSubview(entranceBlur)
    content.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open)))
    addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(drag)))
    accessibilityIdentifier = "simulator-preview"
    isHidden = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  isolated deinit { refreshTimer?.invalidate(); stream?.stop() }

  func setSource(_ json: String) {
    let next = SimulatorStreamView.shared(json)
    guard next !== stream else { return }
    stream?.stop()
    stream?.removeFromSuperview()
    stream = next
    next?.preview = self
    if next == nil { isHidden = true } else { attach() }
    superview?.setNeedsLayout()
  }

  func attach() {
    guard let stream, stream.fullscreen?.window == nil else { return }
    stream.compact = true
    content.addSubview(stream)
    stream.frame = content.bounds
    isHidden = false
    setNeedsLayout()
    superview?.setNeedsLayout()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    refreshTimer?.invalidate()
    refreshTimer = nil
    if window == nil { finishEntrance(); needsEntrance = true }
    if window != nil {
      attach()
      refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.125, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.refreshBackdrop() }
      }
    }
  }

  func layout(in available: CGRect) {
    area = available.insetBy(dx: 12, dy: 12)
    guard let stream else { return }
    isHidden = stream.fullscreen?.window != nil || area.width < 116 || area.height < 132
    guard !isHidden else { return }
    let height = min(268, area.height)
    let width = min(144, area.width, max(116, (height - 48) / 2 + 8))
    bounds.size = CGSize(width: width, height: height)
    frame.origin = CGPoint(
      x: area.minX + (area.width - bounds.width) * position.x,
      y: area.minY + (area.height - bounds.height) * position.y)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    content.frame = CGRect(x: 4, y: 44, width: bounds.width - 8, height: max(0, bounds.height - 48))
    var displayFrame = content.frame
    var cornerRadius: CGFloat = 12
    if let stream, stream.superview === content {
      stream.frame = content.bounds
      stream.layoutIfNeeded()
      displayFrame = stream.convert(stream.displayFrame, to: self)
      cornerRadius = stream.displayCornerRadius
    }
    let backdropFrame = displayFrame.insetBy(dx: -Self.backdropOutset, dy: -Self.backdropOutset)
    if backdrop.bounds.size != backdropFrame.size || blurCornerRadius != cornerRadius { blurMask = nil }
    blurCornerRadius = cornerRadius
    backdrop.frame = backdropFrame
    expand.frame = CGRect(x: 4, y: 0, width: bounds.width / 2 - 4, height: 44)
    close.frame = CGRect(x: bounds.width / 2, y: 0, width: bounds.width / 2 - 4, height: 44)
    for button in [expand, close] {
      button.layoutIfNeeded()
      button.imageView?.layer.shadowColor = UIColor.systemBackground.resolvedColor(with: traitCollection).cgColor
      if let icon = button.imageView {
        icon.layer.shadowPath = UIBezierPath(roundedRect: icon.bounds.insetBy(dx: -3, dy: -2), cornerRadius: 4).cgPath
      }
    }
    refreshBackdrop()
    entranceBlur.frame = bounds
    entranceBlur.layer.mask?.frame = entranceBlur.bounds
    layer.mask?.frame = backdrop.frame.union(bounds)
    if needsEntrance, !isHidden, window != nil, bounds.height > 48 { beginEntrance() }
  }

  private func finishEntrance() {
    entranceTimer?.invalidate()
    entranceTimer = nil
    layer.mask = nil
    entranceBlur.effect = nil
    entranceBlur.isHidden = true
    entranceBlur.layer.mask = nil
  }

  private func beginEntrance() {
    finishEntrance()
    needsEntrance = false
    let reducedMotion = UIAccessibility.isReduceMotionEnabled
    let duration = reducedMotion ? 0.18 : 0.32
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = duration
    fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
    let reveal = CALayer()
    reveal.frame = backdrop.frame.union(bounds)
    reveal.backgroundColor = UIColor.white.cgColor
    layer.mask = reveal
    reveal.add(fade, forKey: "entrance")
    if !reducedMotion {
      // Native blur stays opaque; its mask reveals the sharp live renderer.
      let clear = CALayer()
      clear.frame = entranceBlur.bounds
      clear.backgroundColor = UIColor.white.cgColor
      clear.opacity = 0
      entranceBlur.layer.mask = clear
      entranceBlur.effect = UIBlurEffect(style: .regular)
      entranceBlur.isHidden = false
      let sharpen = fade.copy() as! CABasicAnimation
      sharpen.fromValue = 1
      sharpen.toValue = 0
      clear.add(sharpen, forKey: "entrance")
    }
    entranceTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated { self?.finishEntrance() }
    }
    recordEntrance()
  }

  private func recordEntrance() {
    guard LodyUIVerify.enabled else { return }
    let started = CACurrentMediaTime()
    var samples: [[String: Double]] = [["seconds": 0, "opacity": 0, "blurMask": 0]]
    Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] timer in
      let finished = MainActor.assumeIsolated {
        guard let self else { return true }
        if self.entranceTimer != nil, self.layer.presentation()?.isHidden != false { return false }
        let mask = self.entranceBlur.layer.mask
        samples.append(["seconds": CACurrentMediaTime() - started,
          "opacity": Double((self.layer.mask?.presentation() ?? self.layer.mask)?.opacity ?? 1),
          "blurMask": Double((mask?.presentation() ?? mask)?.opacity ?? 0)])
        guard self.entranceTimer == nil else { return false }
        let result: [String: Any] = ["samples": samples,
          "completed": !self.isHidden && self.window != nil,
          "blurRemoved": self.entranceBlur.isHidden && self.entranceBlur.effect == nil]
        if let data = try? JSONSerialization.data(withJSONObject: result) {
          try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("lody-simulator-entrance-\(UUID().uuidString).json"))
        }
        return true
      }
      if finished { timer.invalidate() }
    }
  }

  private func refreshBackdrop() {
    guard !isHidden, window != nil, let superview, bounds.width > 0, bounds.height > 0 else { return }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: backdrop.bounds.size, format: format)
    if blurMask == nil {
      let shape = CIFilter.roundedRectangleGenerator()
      shape.extent = backdrop.bounds.insetBy(dx: Self.backdropOutset - 8, dy: Self.backdropOutset - 8)
      shape.radius = Float(blurCornerRadius + 8)
      shape.color = .white
      let feather = CIFilter.gaussianBlur()
      feather.inputImage = shape.outputImage?.composited(over: CIImage(color: .black).cropped(to: backdrop.bounds)).clampedToExtent()
      feather.radius = 20
      blurMask = feather.outputImage?.cropped(to: backdrop.bounds)
    }
    // Capture only the chat behind us; the live renderer stays on its original path.
    let image = renderer.image { context in
      let origin = convert(backdrop.frame.origin, to: superview)
      superview.backgroundColor?.setFill()
      context.fill(backdrop.bounds)
      for view in superview.subviews where view !== self && !view.isHidden {
        let frame = view.convert(view.bounds, to: superview).offsetBy(dx: -origin.x, dy: -origin.y)
        guard frame.intersects(backdrop.bounds) else { continue }
        context.cgContext.saveGState()
        context.cgContext.translateBy(x: frame.minX, y: frame.minY)
        view.layer.render(in: context.cgContext)
        context.cgContext.restoreGState()
      }
    }
    guard let input = CIImage(image: image), let blurMask else { return }
    let blur = CIFilter.maskedVariableBlur()
    blur.inputImage = input.clampedToExtent()
    blur.mask = blurMask
    blur.radius = 28
    let tint = UIColor.systemBackground.resolvedColor(with: traitCollection).withAlphaComponent(0.55)
    let fade = CIFilter.blendWithMask()
    fade.inputImage = blur.outputImage.map { CIImage(color: CIColor(color: tint)).cropped(to: input.extent).composited(over: $0) }
    fade.backgroundImage = CIImage(color: .clear).cropped(to: input.extent)
    fade.maskImage = blurMask
    guard let output = fade.outputImage,
          let cgImage = Self.imageContext.createCGImage(output, from: input.extent) else { return }
    backdrop.image = UIImage(cgImage: cgImage)
  }

  @objc private func open() { onAction?("expand") }

  @objc private func drag(_ gesture: UIPanGestureRecognizer) {
    if gesture.state == .began { dragStart = frame.origin }
    let translation = gesture.translation(in: superview)
    let travel = CGSize(width: max(1, area.width - bounds.width), height: max(1, area.height - bounds.height))
    position = CGPoint(
      x: min(1, max(0, (dragStart.x + translation.x - area.minX) / travel.width)),
      y: min(1, max(0, (dragStart.y + translation.y - area.minY) / travel.height)))
    if gesture.state == .ended || gesture.state == .cancelled {
      position.x = position.x < 0.5 ? 0 : 1
      UIView.animate(withDuration: 0.2) { self.layout(in: self.area.insetBy(dx: -12, dy: -12)) }
    } else {
      layout(in: area.insetBy(dx: -12, dy: -12))
    }
  }
}
