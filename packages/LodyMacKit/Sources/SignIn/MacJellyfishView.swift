import AppKit
import MetalKit

struct MacJellyfishMotion {
  static let revealDuration: TimeInterval = 1.6
  static let leaveDuration: TimeInterval = 1
  static let cell: CGFloat = 3

  var reduceMotion: Bool

  @MainActor static var system: MacJellyfishMotion {
    MacJellyfishMotion(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
  }

  var leaveDuration: TimeInterval { reduceMotion ? 0 : Self.leaveDuration }

  func reveal(elapsed: TimeInterval) -> Float {
    reduceMotion ? 1 : Float(min(1, max(0, elapsed / Self.revealDuration)))
  }

  func leave(elapsed: TimeInterval?) -> Float {
    guard let elapsed else { return 0 }
    guard leaveDuration > 0 else { return 1 }
    return Float(min(1, max(0, elapsed / leaveDuration)))
  }

  static func grid(for size: NSSize) -> (columns: Int, rows: Int) {
    (max(1, Int(size.width / cell)), max(1, Int(size.height / cell)))
  }
}

private struct MacJellyfishUniforms {
  var r: SIMD2<Float>
  var m: SIMD2<Float>
  var paper: SIMD4<Float>
  var ink: SIMD4<Float>
  var t: Float
  var reveal: Float
  var leave: Float
  var pad: Float = 0
}

private struct MacPipelineBox: @unchecked Sendable {
  let state: MTLRenderPipelineState
}

@MainActor
final class MacJellyfishView: NSView, MTKViewDelegate {
  static let paper = SIMD4<Float>(0.094, 0.094, 0.102, 1)
  static let ink = SIMD4<Float>(0.8, 0.8, 0.82, 1)

  private let motion: MacJellyfishMotion
  private let metal = MTKView()
  private var queue: MTLCommandQueue?
  private var pipeline: MTLRenderPipelineState?
  private let epoch = CACurrentMediaTime()
  private var revealStart: CFTimeInterval?
  private var leaveStart: CFTimeInterval?
  private var pointer = SIMD2<Float>(0.5, 0.5)
  private var target = SIMD2<Float>(0.5, 0.5)
  private var occlusion: NSObjectProtocol?

  init(motion: MacJellyfishMotion) {
    self.motion = motion
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = Self.color(Self.paper)
    setAccessibilityElement(false)
    setAccessibilityIdentifier("sign-in-visual")
    metal.device = MTLCreateSystemDefaultDevice()
    metal.delegate = self
    metal.autoResizeDrawable = false
    metal.colorPixelFormat = .bgra8Unorm
    metal.clearColor = MTLClearColor(red: Double(Self.paper.x), green: Double(Self.paper.y), blue: Double(Self.paper.z), alpha: 1)
    metal.preferredFramesPerSecond = 60
    metal.isPaused = true
    metal.enableSetNeedsDisplay = true
    addSubview(metal)
    prepare()
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
  }

  func start() {
    revealStart = revealStart ?? CACurrentMediaTime()
    refresh()
  }

  func leave(completion: @escaping @MainActor () -> Void) {
    leaveStart = CACurrentMediaTime()
    refresh()
    let duration = motion.leaveDuration
    guard duration > 0 else { completion(); return }
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { MainActor.assumeIsolated { completion() } }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
    occlusion = nil
    if let window {
      occlusion = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
    }
    refresh()
  }

  override func layout() {
    super.layout()
    let grid = MacJellyfishMotion.grid(for: bounds.size)
    let size = NSSize(width: CGFloat(grid.columns) * MacJellyfishMotion.cell, height: CGFloat(grid.rows) * MacJellyfishMotion.cell)
    metal.frame = NSRect(x: 0, y: bounds.height - size.height, width: size.width, height: size.height)
    metal.drawableSize = CGSize(width: grid.columns, height: grid.rows)
    metal.layer?.magnificationFilter = .nearest
    if metal.isPaused { metal.needsDisplay = true }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
  }

  override func mouseMoved(with event: NSEvent) {
    guard bounds.width > 0, bounds.height > 0 else { return }
    let point = convert(event.locationInWindow, from: nil)
    target = SIMD2(Float(point.x / bounds.width), Float(point.y / bounds.height))
  }

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

  func draw(in view: MTKView) {
    guard let pipeline, let queue, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
          let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
    let now = CACurrentMediaTime()
    pointer += (target - pointer) * 0.05
    var uniforms = MacJellyfishUniforms(
      r: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
      m: pointer,
      paper: Self.paper,
      ink: Self.ink,
      t: motion.reduceMotion ? 3 : Float(3 + now - epoch),
      reveal: motion.reveal(elapsed: revealStart.map { now - $0 } ?? 0),
      leave: motion.leave(elapsed: leaveStart.map { now - $0 })
    )
    encoder.setRenderPipelineState(pipeline)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MacJellyfishUniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    buffer.present(drawable)
    buffer.commit()
  }

  private func prepare() {
    guard let device = metal.device else { return }
    queue = device.makeCommandQueue()
    let format = metal.colorPixelFormat
    device.makeLibrary(source: MacJellyfishShader.source, options: nil) { [weak self] library, _ in
      guard let library else { return }
      let descriptor = MTLRenderPipelineDescriptor()
      descriptor.vertexFunction = library.makeFunction(name: MacJellyfishShader.vertex)
      descriptor.fragmentFunction = library.makeFunction(name: MacJellyfishShader.fragment)
      descriptor.colorAttachments[0].pixelFormat = format
      guard let state = try? device.makeRenderPipelineState(descriptor: descriptor) else { return }
      let box = MacPipelineBox(state: state)
      Task { @MainActor in
        self?.pipeline = box.state
        self?.refresh()
      }
    }
  }

  private func refresh() {
    let visible = window?.occlusionState.contains(.visible) == true
    let running = pipeline != nil && visible && !motion.reduceMotion
    metal.enableSetNeedsDisplay = !running
    metal.isPaused = !running
    if !running { metal.needsDisplay = true }
  }

  private static func color(_ rgba: SIMD4<Float>) -> CGColor {
    CGColor(srgbRed: CGFloat(rgba.x), green: CGFloat(rgba.y), blue: CGFloat(rgba.z), alpha: CGFloat(rgba.w))
  }
}
