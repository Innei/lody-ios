import AppKit
import MetalKit

private struct MacEffortHeatUniforms {
  var track: SIMD4<Float>
  var start: SIMD4<Float>
  var violet: SIMD4<Float>
  var dotOff: SIMD4<Float>
  var frame: SIMD4<Float>
  var clock: SIMD4<Float>
  var thumb: SIMD4<Float>
}

private extension NSColor {
  var shaderColor: SIMD4<Float> {
    let color = usingColorSpace(.deviceRGB) ?? .black
    return SIMD4(Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent), Float(color.alphaComponent))
  }
}

/// Retains native NSSlider tracking, keyboard and accessibility; Metal only renders the control.
@MainActor
final class MacEffortSlider: NSSlider {
  private let heat = MacEffortHeat()
  override init(frame: NSRect) {
    super.init(frame: frame)
    minValue = 0
    maxValue = 1
    isContinuous = true
    allowsTickMarkValuesOnly = true
    focusRingType = .exterior
    addSubview(heat)
    heat.isHidden = !heat.available
  }
  required init?(coder: NSCoder) { nil }
  override func layout() { super.layout(); heat.frame = bounds }
  override func draw(_ dirtyRect: NSRect) { if !heat.available { super.draw(dirtyRect) } }
  func render(value: Double, steps: Int, ultra: Bool, fast: Bool) {
    numberOfTickMarks = steps + 1
    doubleValue = value
    heat.fraction = Float(value)
    heat.steps = Float(steps)
    heat.ultra = ultra
    heat.fast = fast
    heat.wake()
  }
  func suspend() { heat.suspended = true; heat.isPaused = true }
  func resume() { heat.suspended = false; heat.wake() }
}

@MainActor
private final class MacEffortHeat: MTKView, MTKViewDelegate {
  private var queue: MTLCommandQueue?
  private var pipeline: MTLRenderPipelineState?
  var available: Bool { pipeline != nil }
  var fraction: Float = 0
  var steps: Float = 1
  var ultra = false
  var suspended = true
  private var motion: Bool { !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
  var fast = false
  private var thumb: Float?
  private var velocity: Float = 0
  private var ultraAmount: Float = 0
  private var fastAmount: Float = 0
  private var flow: Float = 0
  private var lastFrame: CFTimeInterval?

  init() {
    let gpu = MTLCreateSystemDefaultDevice()
    super.init(frame: .zero, device: gpu)
    clearColor = MTLClearColorMake(0, 0, 0, 0)
    layer?.isOpaque = false
    preferredFramesPerSecond = 60
    isPaused = true
    delegate = self
    setAccessibilityElement(false)
    if let gpu {
      do {
        let library = try gpu.makeDefaultLibrary(bundle: .lodyMac)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "heatVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "heatFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try gpu.makeRenderPipelineState(descriptor: descriptor)
        queue = gpu.makeCommandQueue()
      } catch { NSLog("Effort shader unavailable: %@", String(describing: error)) }
    }
    for name in [NSApplication.didBecomeActiveNotification, NSWindow.didChangeOcclusionStateNotification] {
      NotificationCenter.default.addObserver(self, selector: #selector(environmentChanged), name: name, object: nil)
    }
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(environmentChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
  }
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  isolated deinit {
    NotificationCenter.default.removeObserver(self)
    NSWorkspace.shared.notificationCenter.removeObserver(self)
  }
  override var isOpaque: Bool { false }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if window == nil { isPaused = true } else { wake() } }
  override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); wake() }
  override func layout() { super.layout(); wake() }
  @objc private func environmentChanged() { wake() }
  func wake() {
    guard !suspended, window?.isVisible == true, NSApp.isActive, available else { isPaused = true; return }
    lastFrame = nil
    isPaused = false
  }
  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
  func draw(in view: MTKView) {
    guard !suspended, window?.isVisible == true, NSApp.isActive,
      let queue, let pipeline, bounds.width > 32 else { isPaused = true; return }
    let now = CACurrentMediaTime()
    let dt = Float(min(1.0 / 20, lastFrame.map { now - $0 } ?? 1.0 / 60))
    lastFrame = now
    let settled = advance(dt)
    if let descriptor = currentRenderPassDescriptor, let drawable = currentDrawable,
      let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: descriptor)
    {
      var uniforms = makeUniforms()
      effectiveAppearance.performAsCurrentDrawingAppearance { uniforms = makeUniforms() }
      encoder.setRenderPipelineState(pipeline)
      encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MacEffortHeatUniforms>.stride, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
      encoder.endEncoding()
      command.present(drawable)
      command.commit()
    }
    if settled { isPaused = true }
  }
  private var target: Float { 16 + fraction * max(0, Float(bounds.width) - 32) }

  private func advance(_ dt: Float) -> Bool {
    let goal = target
    let goalUltra: Float = ultra ? 1 : 0
    let goalFast: Float = fast ? 1 : 0
    guard motion, var position = thumb else {
      thumb = goal
      velocity = 0
      ultraAmount = goalUltra
      fastAmount = goalFast
      return !(motion && (ultra || fast))
    }
    let stiffness: Float = 520
    let damping = 2 * stiffness.squareRoot() * 0.62
    for _ in 0..<4 {
      velocity += (stiffness * (goal - position) - damping * velocity) * dt / 4
      position += velocity * dt / 4
    }
    let springing = abs(goal - position) > 0.05 || abs(velocity) > 0.5
    if !springing {
      position = goal
      velocity = 0
    }
    thumb = position
    let ease = 1 - exp(-dt * 7)
    ultraAmount += (goalUltra - ultraAmount) * ease
    fastAmount += (goalFast - fastAmount) * ease
    let fading = abs(goalUltra - ultraAmount) > 0.002 || abs(goalFast - fastAmount) > 0.002
    if !fading {
      ultraAmount = goalUltra
      fastAmount = goalFast
    }
    // Float noise inputs lose precision as flow grows; wrapping costs one pattern jump every few minutes of animation.
    flow = (flow + dt * (1 + 1.4 * fastAmount)).truncatingRemainder(dividingBy: 600)
    return !springing && !fading && !ultra && !fast
  }

  private func makeUniforms() -> MacEffortHeatUniforms {
    let width = Float(bounds.width)
    let position = thumb ?? target
    return MacEffortHeatUniforms(
      track: NSColor.tertiarySystemFill.shaderColor,
      start: NSColor.systemBlue.shaderColor,
      violet: NSColor.systemPurple.shaderColor,
      dotOff: NSColor.tertiaryLabelColor.shaderColor,
      frame: SIMD4(width, Float(bounds.height), Float(drawableSize.width) / width, 0),
      clock: SIMD4(flow, ultraAmount, fastAmount, steps),
      thumb: SIMD4(position, (position - 16) / max(1, width - 32), min(1500, max(-1500, velocity)), 0)
    )
  }
}
