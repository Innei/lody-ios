import UIKit
import MetalKit

struct ChatComposerOption: Decodable {
  let id: String
  let title: String
}

struct ChatComposerOptions: Decodable {
  var modelId = ""
  var effort = ""
  var fast: Bool?
  var models: [ChatComposerOption] = []
  var efforts: [ChatComposerOption] = []
}

extension ChatComposerOptions {
  var modelTitle: String {
    models.first { $0.id == modelId }?.title
      ?? (modelId.isEmpty ? LodyStrings.text("native.chat.composer.defaultModel") : modelId)
  }
  var effortTitle: String {
    let title = efforts.first { $0.id == effort }?.title ?? effort
    switch title.lowercased() {
    case "": return LodyStrings.text("native.chat.composer.defaultEffort")
    case "xhigh": return "Extra High"
    default: return title.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }
}

// Render only while Fast or Ultra is visible and motion is allowed.
private final class ChatEffortParticles: MTKView, MTKViewDelegate {
  static let accent = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.70, green: 0.61, blue: 0.91, alpha: 1)
      : UIColor(red: 0.48, green: 0.36, blue: 0.70, alpha: 1)
  }
  private static let renderer: (MTLDevice, MTLCommandQueue, MTLRenderPipelineState)? = {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
    do {
      guard let url = Bundle(for: ChatComposerModelPanel.self).url(forResource: "LodyKitShaders", withExtension: "bundle"),
        let bundle = Bundle(url: url)
      else { throw CocoaError(.fileNoSuchFile) }
      let library = try device.makeDefaultLibrary(bundle: bundle)
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = library.makeFunction(name: "particleVertex")
      descriptor.fragmentFunction = library.makeFunction(name: "particleFragment")
      descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      return (device, queue, try device.makeRenderPipelineState(descriptor: descriptor))
    } catch {
      NSLog("Effort particle shader unavailable: %@", String(describing: error))
      return nil
    }
  }()
  private var started = CACurrentMediaTime()
  var thumbFraction: Float = 1
  var fast = false { didSet { if fast != oldValue { started = CACurrentMediaTime() } } }

  init() {
    super.init(frame: .zero, device: Self.renderer?.0)
    isOpaque = false
    backgroundColor = .clear
    clearColor = MTLClearColorMake(0, 0, 0, 0)
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    preferredFramesPerSecond = 60
    isPaused = true
    layer.cornerRadius = 14
    clipsToBounds = true
    delegate = self
  }
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func setRunning(_ running: Bool) {
    if running && isPaused { started = CACurrentMediaTime() }
    isPaused = !running
    isHidden = !running
  }
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
  func draw(in view: MTKView) {
    guard let (_, queue, pipeline) = Self.renderer,
      let descriptor = currentRenderPassDescriptor, let drawable = currentDrawable,
      let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: descriptor)
    else { return }
    var uniforms = SIMD4<Float>(Float(CACurrentMediaTime() - started) * (fast ? 2.4 : 1), Float(bounds.width), Float(bounds.height), thumbFraction)
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout.size(ofValue: uniforms), index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    command.present(drawable)
    command.commit()
  }


}

private final class ChatEffortSlider: UIControl {
  var steps = 1 { didSet { setNeedsDisplay() } }
  var value: Float = 0 { didSet { setNeedsDisplay(); setNeedsLayout() } }
  var isFast = false { didSet { particles.fast = isFast; updateEnergy() } }
  var isUltra = false { didSet { setNeedsDisplay(); updateEnergy() } }
  private let particles = ChatEffortParticles()

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    isAccessibilityElement = true
    accessibilityTraits = .adjustable
    addSubview(particles)
    for name in [UIAccessibility.reduceMotionStatusDidChangeNotification, UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification] {
      NotificationCenter.default.addObserver(self, selector: #selector(energyEnvironmentChanged(_:)), name: name, object: nil)
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  deinit { NotificationCenter.default.removeObserver(self) }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateEnergy()
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    particles.frame = CGRect(x: 0, y: (bounds.height - 28) / 2, width: bounds.width, height: 28)
    particles.thumbFraction = value
    updateEnergy()
  }
  @objc private func energyEnvironmentChanged(_ notification: Notification) {
    updateEnergy(suspended: notification.name == UIApplication.willResignActiveNotification)
  }
  private func updateEnergy(suspended: Bool = false) {
    let animate = (isUltra || isFast) && window != nil && !isHidden && !suspended && UIApplication.shared.applicationState == .active && !UIAccessibility.isReduceMotionEnabled
    particles.setRunning(animate)
  }

  override func draw(_ rect: CGRect) {
    let track = CGRect(x: 0, y: (bounds.height - 28) / 2, width: bounds.width, height: 28)
    let thumbX = 16 + CGFloat(value) * max(0, bounds.width - 32)
    let path = UIBezierPath(roundedRect: track, cornerRadius: 14)
    UIColor.tertiarySystemFill.setFill()
    path.fill()
    let context = UIGraphicsGetCurrentContext()
    context?.saveGState()
    path.addClip()
    (isUltra ? ChatEffortParticles.accent : UIColor.systemBlue).setFill()
    UIRectFill(CGRect(x: 0, y: track.minY, width: thumbX, height: track.height))
    for index in 0...steps {
      let x = 16 + CGFloat(index) / CGFloat(steps) * max(0, bounds.width - 32)
      (x <= thumbX ? UIColor.white.withAlphaComponent(0.4) : UIColor.tertiaryLabel).setFill()
      UIBezierPath(ovalIn: CGRect(x: x - 2.5, y: bounds.midY - 2.5, width: 5, height: 5)).fill()
    }
    context?.restoreGState()
    context?.saveGState()
    context?.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.12).cgColor)
    UIColor.white.setFill()
    UIBezierPath(ovalIn: CGRect(x: thumbX - 16, y: bounds.midY - 16, width: 32, height: 32)).fill()
    context?.restoreGState()

  }

  private func move(to point: CGPoint) {
    let fraction = max(0, min(1, (point.x - 16) / max(1, bounds.width - 32)))
    setStep(Int((fraction * CGFloat(steps)).rounded()))
  }
  private func setStep(_ step: Int) {
    let next = Float(min(steps, max(0, step))) / Float(steps)
    guard value != next else { return }
    value = next
    sendActions(for: .valueChanged)
  }
  override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
    move(to: touch.location(in: self))
    return true
  }
  override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
    move(to: touch.location(in: self))
    return true
  }
  override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
    if let touch { move(to: touch.location(in: self)) }
  }
  override func accessibilityIncrement() { setStep(Int((value * Float(steps)).rounded()) + 1) }
  override func accessibilityDecrement() { setStep(Int((value * Float(steps)).rounded()) - 1) }
}

final class ChatComposerModelPanel: UIViewController, UIPopoverPresentationControllerDelegate {
  var onModel: ((String) -> Void)?
  var onEffort: ((String) -> Void)?
  var onFast: ((Bool) -> Void)?
  private var options = ChatComposerOptions()
  private let model = UIButton(type: .system)
  private let fast = UIButton(type: .system)
  private let slider = ChatEffortSlider()
  private lazy var modelLeading = model.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24)
  private lazy var modelTrailing = model.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .secondarySystemGroupedBackground
    fast.accessibilityIdentifier = "composer-fast"
    fast.accessibilityLabel = LodyStrings.text("native.chat.composer.fast")
    fast.addTarget(self, action: #selector(toggleFast), for: .touchUpInside)
    model.showsMenuAsPrimaryAction = true
    model.accessibilityIdentifier = "composer-model-menu"
    slider.accessibilityLabel = LodyStrings.text("native.chat.composer.effort")
    slider.accessibilityIdentifier = "composer-effort-slider"
    slider.addTarget(self, action: #selector(changeEffort), for: .valueChanged)
    for child in [model, slider, fast] {
      child.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(child)
    }
    NSLayoutConstraint.activate([
      fast.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
      fast.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
      fast.widthAnchor.constraint(equalToConstant: 44),
      fast.heightAnchor.constraint(equalToConstant: 44),
      modelLeading,
      modelTrailing,
      model.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
      model.heightAnchor.constraint(equalToConstant: 56),
      slider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      slider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
      slider.topAnchor.constraint(equalTo: model.bottomAnchor, constant: 8),
      slider.heightAnchor.constraint(equalToConstant: 44),
    ])
  }

  func render(_ options: ChatComposerOptions) {
    self.options = options
    fast.isHidden = options.fast == nil
    modelLeading.constant = options.fast == nil ? 24 : 56
    modelTrailing.constant = -modelLeading.constant
    let enabled = options.fast == true
    var fastConfiguration = UIButton.Configuration.plain()
    fastConfiguration.image = UIImage(systemName: enabled ? "bolt.fill" : "bolt")
    fastConfiguration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    fastConfiguration.baseForegroundColor = enabled ? .systemBlue : .secondaryLabel
    fastConfiguration.contentInsets = .zero
    if fast.configuration?.image != nil, #available(iOS 26.0, *) {
      fastConfiguration.symbolContentTransition = .init(.replace.byLayer)
    }
    fast.configuration = fastConfiguration
    fast.accessibilityTraits = enabled ? [.button, .selected] : [.button]
    fast.accessibilityValue = LodyStrings.text(enabled ? "native.chat.composer.fastOn" : "native.chat.composer.fastOff")
    preferredContentSize = CGSize(width: 320, height: options.efforts.isEmpty ? 76 : 132)
    var configuration = UIButton.Configuration.plain()
    configuration.baseForegroundColor = options.effort.lowercased() == "ultra" ? ChatEffortParticles.accent : .systemBlue
    configuration.title = options.effortTitle + " ›"
    configuration.subtitle = options.modelTitle
    configuration.titleAlignment = .center
    configuration.titleLineBreakMode = .byTruncatingTail
    configuration.subtitleLineBreakMode = .byTruncatingTail
    configuration.titleTextAttributesTransformer = .init { attributes in
      var attributes = attributes
      attributes.font = .preferredFont(forTextStyle: .headline)
      return attributes
    }
    configuration.subtitleTextAttributesTransformer = .init { attributes in
      var attributes = attributes
      attributes.font = .preferredFont(forTextStyle: .subheadline)
      attributes.foregroundColor = .secondaryLabel
      return attributes
    }
    model.configuration = configuration
    model.accessibilityLabel = LodyStrings.text(
      "native.chat.composer.modelPicker",
      ["model": options.modelTitle, "effort": options.effortTitle]
    )
    model.menu = UIMenu(children: [
      UIAction(title: LodyStrings.text("native.chat.composer.defaultModel"), state: options.modelId.isEmpty ? .on : .off) { [weak self] _ in self?.onModel?("") },
    ] + options.models.map { option in
      UIAction(title: option.title, state: option.id == options.modelId ? .on : .off) { [weak self] _ in self?.onModel?(option.id) }
    })
    slider.isHidden = options.efforts.isEmpty
    slider.steps = max(1, options.efforts.count)
    slider.value = Float(options.efforts.firstIndex { $0.id == options.effort }.map { $0 + 1 } ?? 0) / Float(max(1, options.efforts.count))
    slider.accessibilityValue = options.effortTitle
    slider.isFast = options.fast == true
    slider.isUltra = options.effort.lowercased() == "ultra" && !options.efforts.isEmpty
  }

  @objc private func toggleFast() {
    guard let current = options.fast else { return }
    UISelectionFeedbackGenerator().selectionChanged()
    onFast?(!current)
  }

  @objc private func changeEffort() {
    let index = min(options.efforts.count, max(0, Int((slider.value * Float(options.efforts.count)).rounded())))
    slider.value = Float(index) / Float(max(1, options.efforts.count))
    let effort = index == 0 ? "" : options.efforts[index - 1].id
    guard effort != options.effort else { return }
    UISelectionFeedbackGenerator().selectionChanged()
    onEffort?(effort)
  }

  func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }
}
