import UIKit
import MetalKit

private struct ChatComposerState: Decodable {
  var editable = true
  var canSend = false
  var sending = false
  var notice = ""
  var reconnect = false
  var placeholder = "给 Lody 发消息…"
}

private struct ChatComposerOption: Decodable {
  let id: String
  let title: String
}

private struct ChatComposerOptions: Decodable {
  var modelId = ""
  var effort = ""
  var models: [ChatComposerOption] = []
  var efforts: [ChatComposerOption] = []
}

private extension ChatComposerOptions {
  var modelTitle: String {
    models.first { $0.id == modelId }?.title ?? (modelId.isEmpty ? "默认模型" : modelId)
  }
  var effortTitle: String {
    let title = efforts.first { $0.id == effort }?.title ?? effort
    switch title.lowercased() {
    case "": return "默认"
    case "xhigh": return "Extra High"
    default: return title.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }
}

// The renderer only runs while the Ultra popover is visible and motion is allowed.
private final class ChatUltraParticles: MTKView, MTKViewDelegate {
  static let accent = UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.70, green: 0.61, blue: 0.91, alpha: 1)
      : UIColor(red: 0.48, green: 0.36, blue: 0.70, alpha: 1)
  }
  private static let renderer: (MTLDevice, MTLCommandQueue, MTLRenderPipelineState)? = {
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
    do {
      let library = try device.makeLibrary(source: shader, options: nil)
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = library.makeFunction(name: "particleVertex")
      descriptor.fragmentFunction = library.makeFunction(name: "particleFragment")
      descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
      return (device, queue, try device.makeRenderPipelineState(descriptor: descriptor))
    } catch {
      NSLog("Ultra particle shader unavailable: %@", String(describing: error))
      return nil
    }
  }()
  private var started = CACurrentMediaTime()
  var thumbFraction: Float = 1

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
    var uniforms = SIMD4<Float>(Float(CACurrentMediaTime() - started), Float(bounds.width), Float(bounds.height), thumbFraction)
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout.size(ofValue: uniforms), index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    command.present(drawable)
    command.commit()
  }

  private static let shader = """
  #include <metal_stdlib>
  using namespace metal;
  struct Vertex { float4 position [[position]]; float2 uv; };
  vertex Vertex particleVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    return {float4(p * 2.0 - 1.0, 0, 1), p};
  }
  float random(float n) { return fract(sin(n * 127.1) * 43758.5453); }
  fragment float4 particleFragment(Vertex in [[stage_in]], constant float4 &u [[buffer(0)]]) {
    float2 p = in.uv * u.yz;
    float thumb = 16.0 + u.w * (u.y - 32.0);
    if (distance(p, float2(thumb, u.z * 0.5)) < 16.0) return float4(0);
    float light = 0.0;
    for (int i = 0; i < 48; i++) {
      bool entry = i >= 32;
      if (entry && u.x > 0.65) continue;
      float seed = float(i) + 1.0;
      // Four loose clusters gather slowly on the left, then accelerate to the right.
      float phase = entry
        ? clamp((u.x - random(seed) * 0.1) / 0.5, 0.0, 1.0)
        : fract(u.x * 0.38 + float(i / 8) * 0.25 + random(seed + 19.0) * 0.13);
      float travel = pow(phase, entry ? 1.6 : 2.6);
      float x = -12.0 + travel * (u.y + 24.0);
      float y = u.z * (0.12 + random(seed + 3.0) * 0.76);
      float2 delta = p - float2(x, y);
      float radius = i % 7 == 0 ? 2.1 : 0.85 + random(seed + 7.0) * 0.65;
      float distanceSquared = dot(delta, delta) / (radius * radius);
      float dotLight = exp(-distanceSquared) + 0.12 * exp(-distanceSquared * 0.3);
      float fade = smoothstep(0.0, 0.1, phase) * (1.0 - smoothstep(0.96, 1.0, phase));
      if (entry) fade *= 1.0 - smoothstep(0.45, 0.65, u.x);
      light += dotLight * fade * (0.85 + 0.15 * sin(u.x * 2.0 + seed));
    }
    float alpha = min(light, 1.0);
    return float4(float3(0.96, 0.94, 1.0) * alpha, alpha);
  }
  """
}

private final class ChatEffortSlider: UIControl {
  var steps = 1 { didSet { setNeedsDisplay() } }
  var value: Float = 0 { didSet { setNeedsDisplay(); setNeedsLayout() } }
  var isUltra = false { didSet { setNeedsDisplay(); updateEnergy() } }
  private let particles = ChatUltraParticles()

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
    let animate = isUltra && window != nil && !isHidden && !suspended && UIApplication.shared.applicationState == .active && !UIAccessibility.isReduceMotionEnabled
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
    (isUltra ? ChatUltraParticles.accent : UIColor.systemBlue).setFill()
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

private final class ChatComposerPopover: UIViewController, UIPopoverPresentationControllerDelegate {
  var onModel: ((String) -> Void)?
  var onEffort: ((String) -> Void)?
  private var options = ChatComposerOptions()
  private let model = UIButton(type: .system)
  private let slider = ChatEffortSlider()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .secondarySystemGroupedBackground
    model.showsMenuAsPrimaryAction = true
    model.accessibilityIdentifier = "composer-model-menu"
    slider.accessibilityLabel = "思考强度"
    slider.accessibilityIdentifier = "composer-effort-slider"
    slider.addTarget(self, action: #selector(changeEffort), for: .valueChanged)
    for child in [model, slider] {
      child.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview(child)
    }
    NSLayoutConstraint.activate([
      model.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
      model.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
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
    preferredContentSize = CGSize(width: 320, height: options.efforts.isEmpty ? 76 : 132)
    var configuration = UIButton.Configuration.plain()
    configuration.baseForegroundColor = options.effort.lowercased() == "ultra" ? ChatUltraParticles.accent : .systemBlue
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
    model.accessibilityLabel = "选择模型，\(options.modelTitle)，\(options.effortTitle)"
    model.menu = UIMenu(children: [
      UIAction(title: "默认模型", state: options.modelId.isEmpty ? .on : .off) { [weak self] _ in self?.onModel?("") },
    ] + options.models.map { option in
      UIAction(title: option.title, state: option.id == options.modelId ? .on : .off) { [weak self] _ in self?.onModel?(option.id) }
    })
    slider.isHidden = options.efforts.isEmpty
    slider.steps = max(1, options.efforts.count)
    slider.value = Float(options.efforts.firstIndex { $0.id == options.effort }.map { $0 + 1 } ?? 0) / Float(max(1, options.efforts.count))
    slider.accessibilityValue = options.effortTitle
    slider.isUltra = options.effort.lowercased() == "ultra" && !options.efforts.isEmpty
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

final class ChatComposerView: UIView, UITextViewDelegate {
  private let composer = UIVisualEffectView(effect: nil)
  private let inputSurface = UIVisualEffectView(effect: nil)
  private let input = UITextView()
  private let hint = UILabel()
  private let notice = UIButton(type: .system)
  private let send = UIButton(type: .system)
  private let sendSpinner = UIActivityIndicatorView(style: .medium)
  private let attach = UIButton(type: .system)
  private let attachSurface = UIVisualEffectView(effect: nil)
  private let accessoryBar = UIView()
  private let modelButton = UIButton(type: .system)
  private weak var optionsPopover: ChatComposerPopover?
  private let attachmentBar = ChatAttachmentBar()
  private var attachments: [ChatAttachment] = []
  private let filePicker = ChatAttachmentPicker()
  private let libraryPicker = ChatPhotoLibraryPicker()
  private var inputHeight: NSLayoutConstraint!
  private var accessoryHeight: NSLayoutConstraint!
  private var hintLeading: NSLayoutConstraint!
  private var noticeHeight: NSLayoutConstraint!
  private var attachmentHeight: NSLayoutConstraint!
  private var state = ChatComposerState()
  private var composerOptions = ChatComposerOptions()
  private var composerExpanded = false
  private var pendingDraft: (text: String, attachments: [ChatAttachment])?
  private var lastRestoreToken = 0
  private var hasInitialDraft = false
  private var hasInitialAttachments = false
  private var lastClearToken = 0
  var onSend: (([String: Any]) -> Void)?
  var onReconnect: (() -> Void)?
  var onComposerOptionChange: (([String: String]) -> Void)?
  var onDraftChange: ((String) -> Void)?
  var onHeightChange: ((CGFloat) -> Void)?
  var displayError: String? { didSet { updateComposer() } }
  private var inputLeading: NSLayoutConstraint!
  private var measuredWidth: CGFloat = 0

  func setInputIdentifier(_ id: String) { input.accessibilityIdentifier = id }

  func attachScrollEdge(to scrollView: UIScrollView) {
    if #available(iOS 26.0, *) {
      let edge = UIScrollEdgeElementContainerInteraction()
      edge.scrollView = scrollView
      edge.edge = .bottom
      composer.addInteraction(edge)
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    if abs(input.bounds.width - measuredWidth) > 0.5 {
      measuredWidth = input.bounds.width
      updateComposer()
    }
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
    input.font = .dynamic(of: 17, compatibleWith: traitCollection)
    hint.font = input.font
    notice.titleLabel?.font = .dynamic(of: 13, compatibleWith: traitCollection)
    updateComposer()
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    composer.backgroundColor = .clear
    if #available(iOS 26.0, *) {
      let container = UIGlassContainerEffect()
      container.spacing = 12
      composer.effect = container
      let glass = UIGlassEffect(style: .regular)
      glass.isInteractive = true
      inputSurface.effect = glass
      attachSurface.effect = glass
    }
    input.backgroundColor = .clear
    if #available(iOS 26.0, *) {
      inputSurface.cornerConfiguration = .capsule(maximumRadius: 24)
      attachSurface.cornerConfiguration = .capsule()
    } else {
      inputSurface.layer.cornerRadius = 24
      inputSurface.layer.cornerCurve = .continuous
      inputSurface.clipsToBounds = true
      attachSurface.layer.cornerRadius = 22
      attachSurface.layer.cornerCurve = .continuous
      attachSurface.clipsToBounds = true
      inputSurface.backgroundColor = .secondarySystemBackground
      attachSurface.backgroundColor = .secondarySystemBackground
    }
    input.font = .dynamic(of: 17)
    input.textColor = .label
    input.textContainerInset = UIEdgeInsets(top: 13, left: 16, bottom: 13, right: 46)
    input.delegate = self
    input.accessibilityIdentifier = "session-input"
    input.accessibilityLabel = "消息"
    hint.text = state.placeholder
    hint.font = input.font
    hint.textColor = .placeholderText
    hint.isUserInteractionEnabled = false
    hint.isAccessibilityElement = false
    send.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)), for: .normal)
    send.tintColor = .systemBlue
    sendSpinner.color = .systemBlue
    sendSpinner.isUserInteractionEnabled = false
    sendSpinner.translatesAutoresizingMaskIntoConstraints = false
    send.addSubview(sendSpinner)
    NSLayoutConstraint.activate([
      sendSpinner.centerXAnchor.constraint(equalTo: send.centerXAnchor),
      sendSpinner.centerYAnchor.constraint(equalTo: send.centerYAnchor),
    ])
    send.accessibilityLabel = "发送"
    send.accessibilityIdentifier = "session-send"
    send.addTarget(self, action: #selector(submit), for: .touchUpInside)
    NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    attach.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
    attach.configuration = .plain()
    attach.configuration?.cornerStyle = .capsule
    attach.tintColor = .secondaryLabel
    attach.accessibilityLabel = "添加附件"
    attach.accessibilityIdentifier = "session-attach"
    attach.showsMenuAsPrimaryAction = true
    attach.menu = UIMenu(children: [
      UIAction(title: "最近照片", image: UIImage(systemName: "photo")) { [weak self] _ in self?.presentRecentPhotos() },
      UIAction(title: "照片图库", image: UIImage(systemName: "photo.on.rectangle.angled")) { [weak self] _ in
        guard let self, let controller = self.presenter() else { return }
        self.libraryPicker.present(from: controller)
      },
      UIAction(title: "文件", image: UIImage(systemName: "folder")) { [weak self] _ in
        guard let self, let controller = self.presenter() else { return }
        self.filePicker.files(from: controller)
      },
    ])
    modelButton.accessibilityIdentifier = "session-model"
    modelButton.addTarget(self, action: #selector(presentComposerOptions), for: .touchUpInside)
    modelButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    filePicker.onPick = { [weak self] picked in self?.addAttachments(picked) }
    libraryPicker.onPick = { [weak self] picked in self?.addAttachments(picked) }
    attachmentBar.onPreview = { [weak self] id in
      guard let self, let index = self.attachments.firstIndex(where: { $0.id == id }), let controller = self.presenter() else { return }
      controller.present(ChatAttachmentPreview(self.attachments, index: index), animated: true)
    }
    attachmentBar.onRemove = { [weak self] id in
      guard let self else { return }
      self.attachments.removeAll { $0.id == id }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      self.updateComposer()
    }
    notice.titleLabel?.font = .dynamic(of: 13)
    notice.titleLabel?.numberOfLines = 0
    notice.addTarget(self, action: #selector(reconnect), for: .touchUpInside)
    addSubview(composer)
    composer.contentView.addSubview(notice)
    composer.contentView.addSubview(attachmentBar)
    composer.contentView.addSubview(attachSurface)
    composer.contentView.addSubview(inputSurface)
    attachSurface.contentView.addSubview(attach)
    for view in [input, hint, accessoryBar, modelButton, send] {
      inputSurface.contentView.addSubview(view)
    }
    for view in [composer, inputSurface, attachSurface, notice, attachmentBar, input, hint, accessoryBar, send, attach, modelButton] {
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    inputHeight = input.heightAnchor.constraint(equalToConstant: 48)
    accessoryHeight = accessoryBar.heightAnchor.constraint(equalToConstant: 0)
    hintLeading = hint.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 21)
    noticeHeight = notice.heightAnchor.constraint(equalToConstant: 0)
    attachmentHeight = attachmentBar.heightAnchor.constraint(equalToConstant: 0)
    inputLeading = inputSurface.leadingAnchor.constraint(equalTo: attachSurface.trailingAnchor, constant: 8)
    NSLayoutConstraint.activate([
      composer.topAnchor.constraint(equalTo: topAnchor),
      composer.leadingAnchor.constraint(equalTo: leadingAnchor),
      composer.trailingAnchor.constraint(equalTo: trailingAnchor),
      composer.bottomAnchor.constraint(equalTo: bottomAnchor),
      notice.topAnchor.constraint(equalTo: composer.topAnchor), notice.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 20),
      notice.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -20), noticeHeight,
      attachmentBar.topAnchor.constraint(equalTo: notice.bottomAnchor),
      attachmentBar.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 16),
      attachmentBar.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -16), attachmentHeight,
      inputSurface.topAnchor.constraint(equalTo: attachmentBar.bottomAnchor, constant: 8),
      attachSurface.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 16),
      attachSurface.bottomAnchor.constraint(equalTo: inputSurface.bottomAnchor, constant: -2),
      attachSurface.widthAnchor.constraint(equalToConstant: 44), attachSurface.heightAnchor.constraint(equalToConstant: 44),
      inputLeading,
      inputSurface.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -16),
      inputSurface.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -8),
      attach.topAnchor.constraint(equalTo: attachSurface.contentView.topAnchor),
      attach.bottomAnchor.constraint(equalTo: attachSurface.contentView.bottomAnchor),
      attach.leadingAnchor.constraint(equalTo: attachSurface.contentView.leadingAnchor),
      attach.trailingAnchor.constraint(equalTo: attachSurface.contentView.trailingAnchor),
      input.topAnchor.constraint(equalTo: inputSurface.contentView.topAnchor),
      input.leadingAnchor.constraint(equalTo: inputSurface.contentView.leadingAnchor),
      input.trailingAnchor.constraint(equalTo: inputSurface.contentView.trailingAnchor), inputHeight,
      accessoryBar.topAnchor.constraint(equalTo: input.bottomAnchor),
      accessoryBar.leadingAnchor.constraint(equalTo: inputSurface.contentView.leadingAnchor),
      accessoryBar.trailingAnchor.constraint(equalTo: inputSurface.contentView.trailingAnchor),
      accessoryBar.bottomAnchor.constraint(equalTo: inputSurface.contentView.bottomAnchor), accessoryHeight,
      hintLeading, hint.topAnchor.constraint(equalTo: input.topAnchor, constant: 13),
      hint.trailingAnchor.constraint(lessThanOrEqualTo: send.leadingAnchor),
      send.trailingAnchor.constraint(equalTo: inputSurface.contentView.trailingAnchor, constant: -2),
      send.bottomAnchor.constraint(equalTo: inputSurface.contentView.bottomAnchor, constant: -2),
      send.widthAnchor.constraint(equalToConstant: 44), send.heightAnchor.constraint(equalToConstant: 44),
      modelButton.leadingAnchor.constraint(greaterThanOrEqualTo: inputSurface.contentView.leadingAnchor, constant: 2),
      modelButton.centerYAnchor.constraint(equalTo: send.centerYAnchor),
      modelButton.heightAnchor.constraint(equalToConstant: 44),
      modelButton.trailingAnchor.constraint(equalTo: send.leadingAnchor, constant: -2),
    ])
    updateComposer()
  }

  func setInitialDraft(_ text: String) {
    guard !hasInitialDraft else { return }
    hasInitialDraft = true
    guard pendingDraft == nil else { return }
    input.text = text
    updateComposer()
  }
  func setStoredDraft(_ text: String) {
    guard !text.isEmpty, input.text.isEmpty else { return }
    input.text = text
    updateComposer()
  }
  private func saveDraft() {
    onDraftChange?(input.text ?? "")
  }
  @objc private func appDidEnterBackground() { saveDraft() }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { saveDraft() }
  }
  func setInitialAttachments(_ json: String) {
    guard !hasInitialAttachments else { return }
    struct DraftAttachment: Decodable {
      let id: String
      let name: String
      let uri: URL
      let kind: String
    }
    guard let drafts = try? JSONDecoder().decode([DraftAttachment].self, from: Data(json.utf8)),
      drafts.allSatisfy({ $0.uri.isFileURL && ($0.kind == "image" || $0.kind == "file") }) else { return }
    hasInitialAttachments = true
    guard pendingDraft == nil else { return }
    attachments = drafts.map { ChatAttachment(id: $0.id, name: $0.name, url: $0.uri, isImage: $0.kind == "image") }
    updateComposer()
  }
  func clearDraft(token: Int) {
    guard token > lastClearToken else { return }
    lastClearToken = token
    guard pendingDraft != nil else { return }
    acknowledgedSendID = pendingSendID
    pendingDraft = nil
    pendingSendID = nil
    updateComposer()
    saveDraft()
  }
  func restoreDraft(token: Int) {
    guard token > lastRestoreToken else { return }
    lastRestoreToken = token
    let id = pendingSendID ?? UUID().uuidString.lowercased()
    ChatSendHandoff.cancel(id: id)
    pendingSendID = nil
    if let draft = pendingDraft {
      if (input.text ?? "").isEmpty && attachments.isEmpty {
        input.text = draft.text
        attachments = draft.attachments
      } else {
        failedDraft = ChatPendingSend(id: id, text: draft.text, attachments: draft.attachments.map { item in
          ChatPendingSend.Attachment(id: item.id, name: item.name, uri: item.url.absoluteString, kind: item.isImage ? "image" : "file")
        }, status: "", failed: true)
      }
      pendingDraft = nil
    }
    updateComposer()
  }
  private var pendingSendID: String?
  private var acknowledgedSendID: String?
  private var restoredSendID: String?
  private var failedDraft: ChatPendingSend?

  func setPendingSend(_ pending: ChatPendingSend) {
    guard pending.id != restoredSendID, pending.id != acknowledgedSendID else { return }
    if pending.failed == true {
      if pendingSendID == pending.id {
        restoreDraft(token: lastRestoreToken + 1)
        restoredSendID = pending.id
      } else if (input.text ?? "").isEmpty && attachments.isEmpty {
        input.text = pending.text
        attachments = pending.attachments.compactMap { item in
          guard let url = URL(string: item.uri), url.isFileURL else { return nil }
          return ChatAttachment(id: item.id, name: item.name, url: url, isImage: item.kind == "image")
        }
        restoredSendID = pending.id
        updateComposer()
      } else {
        failedDraft = pending
        updateComposer()
      }
      return
    }
    guard pendingSendID != pending.id else { return }
    pendingSendID = pending.id
    pendingDraft = (pending.text, pending.attachments.compactMap { item in
      guard let url = URL(string: item.uri), url.isFileURL else { return nil }
      return ChatAttachment(id: item.id, name: item.name, url: url, isImage: item.kind == "image")
    })
    updateComposer()
  }

  private func takeDraft() {
    guard pendingDraft == nil else { return }
    pendingDraft = (input.text ?? "", attachments)
    input.text = ""
    attachments = []
  }
  private func presentRecentPhotos() {
    guard let controller = presenter() else { return }
    let sheet = ChatAttachmentSheet()
    sheet.onPick = { [weak self] picked in self?.addAttachments(picked) }
    controller.present(sheet, animated: true)
  }
  private func addAttachments(_ picked: [ChatAttachment]) {
    attachments += picked.filter { new in !attachments.contains { $0.id == new.id } }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    updateComposer()
  }
  private func presenter() -> UIViewController? {
    var responder: UIResponder? = next
    while let current = responder {
      if let controller = current as? UIViewController { return controller.presentedViewController ?? controller }
      responder = current.next
    }
    return window?.rootViewController
  }
  func setComposerState(_ json: String) {
    guard let value = try? JSONDecoder().decode(ChatComposerState.self, from: Data(json.utf8)) else { return }
    if value.sending && !state.sending { takeDraft() }
    state = value
    updateComposer()
  }
  func setComposerOptions(_ json: String) {
    guard let value = try? JSONDecoder().decode(ChatComposerOptions.self, from: Data(json.utf8)) else { return }
    composerOptions = value
    updateComposerOptions()
  }
  private func updateComposer() {
    let sending = state.sending || pendingDraft != nil
    let expanded = input.isFirstResponder
    let expansionChanged = composerExpanded != expanded
    if expansionChanged && window != nil { layoutIfNeeded() }
    composerExpanded = expanded
    input.isEditable = state.editable
    attach.isEnabled = state.editable && !sending
    attach.alpha = attach.isEnabled ? 1 : 0.5
    attachmentBar.isUserInteractionEnabled = state.editable && !sending
    attachmentBar.render(attachments)
    attachmentHeight.constant = attachments.isEmpty ? 0 : 42
    hint.text = state.placeholder
    hint.isHidden = !input.text.isEmpty
    send.isEnabled = failedDraft == nil && displayError == nil && state.editable && state.canSend && !sending && (!input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    send.accessibilityLabel = sending ? "正在发送" : "发送"
    send.setImage(sending ? nil : UIImage(systemName: "arrow.up.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)), for: .normal)
    if sending { sendSpinner.startAnimating() } else { sendSpinner.stopAnimating() }
    let noticeText = failedDraft == nil ? (displayError ?? state.notice) : "有一条未发出的消息 · 点此合并到草稿"
    let canReconnect = failedDraft != nil || displayError != nil || state.reconnect
    notice.setTitle(noticeText, for: .normal)
    notice.setTitleColor(canReconnect ? .systemBlue : .secondaryLabel, for: .normal)
    notice.isUserInteractionEnabled = canReconnect
    notice.accessibilityTraits = canReconnect ? .button : .staticText
    let noticeSize = notice.sizeThatFits(CGSize(width: max(1, bounds.width - 40), height: .greatestFiniteMagnitude))
    noticeHeight.constant = noticeText.isEmpty ? 0 : max(44, noticeSize.height + 12)
    accessoryHeight.constant = expanded ? 44 : 0
    input.textContainerInset = UIEdgeInsets(top: 13, left: 16, bottom: 13, right: expanded ? 16 : 46)
    hintLeading.constant = 21
    let height = input.sizeThatFits(CGSize(width: max(1, input.bounds.width), height: .greatestFiniteMagnitude)).height
    inputHeight.constant = min(140, max(expanded ? 68 : 48, height))
    input.isScrollEnabled = height > 140
    updateComposerOptions()
    onHeightChange?(noticeHeight.constant + attachmentHeight.constant + inputHeight.constant + accessoryHeight.constant + 16)
    setNeedsLayout()
    if expansionChanged && window != nil && !UIAccessibility.isReduceMotionEnabled {
      UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
        self.layoutIfNeeded()
      }
    }
  }
  private func updateComposerOptions() {
    modelButton.isHidden = !composerExpanded || composerOptions.models.isEmpty
    modelButton.isEnabled = state.editable && !state.sending && pendingDraft == nil
    let title = NSMutableAttributedString(string: composerOptions.modelTitle, attributes: [.foregroundColor: UIColor.label])
    if !composerOptions.efforts.isEmpty || !composerOptions.effort.isEmpty {
      title.append(NSAttributedString(string: " " + composerOptions.effortTitle, attributes: [.foregroundColor: UIColor.secondaryLabel]))
    }
    title.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .caption1), range: NSRange(location: 0, length: title.length))
    var configuration = UIButton.Configuration.plain()
    configuration.attributedTitle = AttributedString(title)
    configuration.image = UIImage(systemName: "chevron.down", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .medium))
    configuration.imagePlacement = .trailing
    configuration.imagePadding = 5
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 6)
    configuration.baseForegroundColor = .secondaryLabel
    configuration.titleLineBreakMode = .byTruncatingTail
    modelButton.configuration = configuration
    modelButton.accessibilityLabel = "模型与强度，" + title.string
    optionsPopover?.render(composerOptions)
    if !modelButton.isEnabled { optionsPopover?.dismiss(animated: true) }
  }
  @objc private func presentComposerOptions() {
    guard modelButton.isEnabled, let controller = presenter(), optionsPopover == nil else { return }
    let panel = ChatComposerPopover()
    panel.onModel = { [weak self] in self?.selectModel($0) }
    panel.onEffort = { [weak self] in self?.selectEffort($0) }
    panel.loadViewIfNeeded()
    panel.render(composerOptions)
    panel.modalPresentationStyle = .popover
    if let popover = panel.popoverPresentationController {
      popover.sourceView = modelButton
      popover.sourceRect = modelButton.bounds
      popover.permittedArrowDirections = .down
      popover.delegate = panel
    }
    optionsPopover = panel
    controller.present(panel, animated: true)
  }
  private func selectModel(_ id: String) {
    guard composerOptions.modelId != id else { return }
    composerOptions.modelId = id
    composerOptions.effort = ""
    composerOptions.efforts = []
    updateComposerOptions()
    onComposerOptionChange?(["modelId": id, "effort": ""])
  }
  private func selectEffort(_ id: String) {
    guard composerOptions.effort != id else { return }
    composerOptions.effort = id
    updateComposerOptions()
    onComposerOptionChange?(["modelId": composerOptions.modelId, "effort": id])
  }
  func textViewDidChange(_ textView: UITextView) { updateComposer() }
  func textViewDidBeginEditing(_ textView: UITextView) { updateComposer() }
  func textViewDidEndEditing(_ textView: UITextView) { updateComposer(); saveDraft() }
  func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    (textView.text as NSString).length - range.length + (text as NSString).length <= 32000
  }
  @objc private func submit() {
    guard send.isEnabled else { return }
    let id = UUID().uuidString.lowercased()
    let body = ([input.text ?? ""] + attachments.filter { !$0.isImage }.map(\.name)).filter { !$0.isEmpty }.joined(separator: "\n")
    if !body.isEmpty { ChatSendHandoff.begin(id: id, text: body, source: input) }
    ChatSendHandoff.beginImages(id: id, attachments: attachments, source: attachmentBar)
    takeDraft()
    saveDraft()
    pendingSendID = id
    guard let draft = pendingDraft else { return }
    updateComposer()
    onSend?([
      "id": id,
      "text": draft.text,
      "attachments": draft.attachments.map {
        ["id": $0.id, "name": $0.name, "uri": $0.url.absoluteString, "kind": $0.isImage ? "image" : "file"]
      },
    ])
  }
  @objc private func reconnect() {
    guard let failed = failedDraft else { onReconnect?(); return }
    input.text = [input.text ?? "", failed.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
    for item in failed.attachments where !attachments.contains(where: { $0.id == item.id }) {
      guard let url = URL(string: item.uri), url.isFileURL else { continue }
      attachments.append(ChatAttachment(id: item.id, name: item.name, url: url, isImage: item.kind == "image"))
    }
    restoredSendID = failed.id
    failedDraft = nil
    updateComposer()
    saveDraft()
  }
}
