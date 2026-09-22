@preconcurrency import AVFoundation
import UIKit

/// The sheet owns one session. Configuration, capture and start/stop share a serial queue.
final class ChatCameraCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
  let session = AVCaptureSession()
  var onReady: ((AVCaptureDevice?, Bool) -> Void)?
  var onPhoto: ((ChatAttachment) -> Void)?
  var onError: ((String) -> Void)?
  private let queue = DispatchQueue(label: "app.innei.lody.attachment-camera")
  private let output = AVCapturePhotoOutput()
  private var input: AVCaptureDeviceInput?
  private var wantsActive = false
  private var generation = 0
  private var captureGeneration: Int?
  private var captureID: Int64?
  private var observers: [NSObjectProtocol] = []
  private var fixtureShots = 0
  private var fixtureEvents: [String] = []
  static var fixture: Bool { LodyUIVerify.enabled && LodyUIVerify.has("--ui-verify-camera") }

  override init() {
    super.init()
    for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
        self?.fail("native.chat.camera.interrupted")
      })
    }
    observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
      DispatchQueue.main.async { self?.setActive(false); self?.onError?("native.chat.camera.interrupted") }
    })
  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
    let session = session
    queue.async { if session.isRunning { session.stopRunning() } }
  }

  // Called on main; serial queue closures preserve the ordering of foreground/visibility changes.
  func setActive(_ active: Bool) {
    guard wantsActive != active else { return }
    wantsActive = active
    queue.async { [self] in
      if Self.fixture {
        fixtureEvents.append(active ? "start" : "stop")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lody-camera-events.json")
        if let data = try? JSONSerialization.data(withJSONObject: fixtureEvents) { try? data.write(to: url, options: .atomic) }
      }
      if !active {
        generation += 1
        captureGeneration = nil
        captureID = nil
        if session.isRunning { session.stopRunning() }
        return
      }
      if Self.fixture {
        DispatchQueue.main.async { [weak self] in self?.onReady?(nil, true) }
        return
      }
      do {
        if input == nil { try configure(position: .back) }
        if !session.isRunning { session.startRunning() }
        guard session.isRunning else { fail("native.chat.camera.unavailable"); return }
        ready()
      } catch { fail("native.chat.camera.unavailable") }
    }
  }

  private func configure(position: AVCaptureDevice.Position) throws {
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
      throw NSError(domain: "LodyCamera", code: 1)
    }
    let next = try AVCaptureDeviceInput(device: device)
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    session.sessionPreset = .photo
    let previous = input
    if let previous { session.removeInput(previous) }
    guard session.canAddInput(next) else {
      if let previous { session.addInput(previous) }
      throw NSError(domain: "LodyCamera", code: 2)
    }
    session.addInput(next)
    input = next
    if !session.outputs.contains(output) {
      guard session.canAddOutput(output) else {
        session.removeInput(next)
        input = nil
        throw NSError(domain: "LodyCamera", code: 3)
      }
      session.addOutput(output)
    }
  }

  private func ready() {
    let device = input?.device
    let canFlip = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
      && AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    DispatchQueue.main.async { [weak self] in self?.onReady?(device, canFlip) }
  }

  func flip() {
    queue.async { [self] in
      guard captureGeneration == nil else { return }
      if Self.fixture { DispatchQueue.main.async { [weak self] in self?.onReady?(nil, true) }; return }
      do {
        try configure(position: input?.device.position == .front ? .back : .front)
        ready()
      } catch { fail("native.chat.camera.unavailable") }
    }
  }

  func focus(at point: CGPoint) {
    queue.async { [self] in
      guard let device = input?.device else { return }
      do {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(.autoFocus) {
          device.focusPointOfInterest = point
          device.focusMode = .autoFocus
        }
        if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(.continuousAutoExposure) {
          device.exposurePointOfInterest = point
          device.exposureMode = .continuousAutoExposure
        }
      } catch { fail("native.chat.camera.interrupted") }
    }
  }

  func capture(flash: AVCaptureDevice.FlashMode, angle: CGFloat) {
    queue.async { [self] in
      guard captureGeneration == nil else { return }
      captureGeneration = generation
      if Self.fixture {
        fixtureShots += 1
        // An explicit offline camera fixture rejects its first shutter press to exercise retry.
        if fixtureShots == 1 {
          captureGeneration = nil
          fail("native.chat.camera.saveFailed")
        } else {
          receive(Self.fixtureImage().jpegData(compressionQuality: 0.9))
        }
        return
      }
      guard session.isRunning, !session.isInterrupted, output.captureReadiness == .ready else {
        captureGeneration = nil
        fail("native.chat.camera.interrupted")
        return
      }
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      captureID = settings.uniqueID
      if output.supportedFlashModes.contains(flash) { settings.flashMode = flash }
      if let connection = output.connection(with: .video) {
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        if connection.isVideoMirroringSupported {
          connection.automaticallyAdjustsVideoMirroring = false
          connection.isVideoMirrored = input?.device.position == .front
        }
      }
      output.capturePhoto(with: settings, delegate: self)
    }
  }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    let data = error == nil ? photo.fileDataRepresentation() : nil
    let id = photo.resolvedSettings.uniqueID
    queue.async { [self] in receive(data, id: id) }
  }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
    guard error != nil else { return }
    let id = resolvedSettings.uniqueID
    queue.async { [self] in
      guard captureID == id, captureGeneration != nil else { return }
      captureGeneration = nil
      captureID = nil
      fail("native.chat.camera.saveFailed")
    }
  }

  private func receive(_ data: Data?, id: Int64? = nil) {
    guard captureID == id, captureGeneration == generation else { return }
    captureGeneration = nil
    captureID = nil
    guard let data, let attachment = Self.store(data) else { fail("native.chat.camera.saveFailed"); return }
    DispatchQueue.main.async { [weak self] in
      guard let self, wantsActive, let onPhoto else { try? FileManager.default.removeItem(at: attachment.url); return }
      onPhoto(attachment)
    }
  }

  static func store(_ data: Data) -> ChatAttachment? {
    guard UIImage(data: data) != nil, let url = ChatAttachment.store(data, name: "Photo.jpg") else { return nil }
    return ChatAttachment(id: UUID().uuidString, name: "Photo.jpg", url: url, isImage: true)
  }

  private func fail(_ key: String) {
    DispatchQueue.main.async { [weak self] in self?.onError?(key) }
  }

  static func fixtureImage() -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: 720, height: 960)).image { context in
      UIColor(red: 0.89, green: 0.82, blue: 0.70, alpha: 1).setFill()
      context.fill(CGRect(x: 0, y: 0, width: 720, height: 960))
      UIColor(red: 0.34, green: 0.47, blue: 0.56, alpha: 1).setFill()
      UIBezierPath(roundedRect: CGRect(x: 110, y: 220, width: 420, height: 560), cornerRadius: 18).fill()
      UIColor.white.setFill()
      UIBezierPath(ovalIn: CGRect(x: 400, y: 540, width: 230, height: 230)).fill()
      ("Camera fixture" as NSString).draw(at: CGPoint(x: 150, y: 310), withAttributes: [
        .font: UIFont.systemFont(ofSize: 36, weight: .medium), .foregroundColor: UIColor.white,
      ])
    }
  }
}

private final class ChatCameraPreview: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
  var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// This exact view moves between the first grid cell and the sheet; the preview is never replaced.
final class ChatAttachmentCameraView: UIView {
  var onCollapse: (() -> Void)?
  var onShutter: ((AVCaptureDevice.FlashMode, CGFloat) -> Void)?
  var onFlip: (() -> Void)?
  var onFocus: ((CGPoint) -> Void)?
  var onRetry: (() -> Void)?
  var onRetake: (() -> Void)?
  var onAdd: (() -> Void)?
  private let preview = ChatCameraPreview()
  private let image = UIImageView()
  private let glyph = UIImageView(image: UIImage(systemName: "camera.fill"))
  private let controls = UIView()
  private let collapse = UIButton(configuration: .glass())
  private let flash = UIButton(configuration: .glass())
  private let shutter = UIButton(configuration: .glass())
  private let flip = UIButton(configuration: .glass())
  private let mode = UILabel()
  private let retake = UIButton(configuration: .glass())
  private let add = UIButton(configuration: .glass())
  private let status = UILabel()
  private let retry = UIButton(configuration: .glass())
  private let focusRing = UIView()
  private var expanded = false
  private var reviewing = false
  private var ready = false
  private var busy = false
  private var flashMode: AVCaptureDevice.FlashMode = .auto
  private var rotation: AVCaptureDevice.RotationCoordinator?
  private var rotationObservation: NSKeyValueObservation?
  var controlInsets = UIEdgeInsets.zero
  var previewLayer: AVCaptureVideoPreviewLayer { preview.previewLayer }

  init(session: AVCaptureSession) {
    super.init(frame: .zero)
    clipsToBounds = true
    backgroundColor = .secondarySystemBackground
    layer.cornerCurve = .continuous
    previewLayer.session = session
    previewLayer.videoGravity = .resizeAspectFill
    image.contentMode = .scaleAspectFill
    image.clipsToBounds = true
    if ChatCameraCapture.fixture { image.image = ChatCameraCapture.fixtureImage() }
    glyph.tintColor = .white
    glyph.backgroundColor = .black.withAlphaComponent(0.4)
    glyph.layer.cornerRadius = 24
    glyph.clipsToBounds = true
    glyph.contentMode = .center
    glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24)
    for item in [preview, image, glyph, controls] { addSubview(item) }
    for button in [collapse, flash, shutter, flip, retake, add, retry] {
      button.configuration?.cornerStyle = .capsule
      button.configuration?.contentInsets = .zero
      button.configuration?.preferredSymbolConfigurationForImage = .init(pointSize: 20, weight: .medium)
    }
    collapse.setImage(UIImage(systemName: "chevron.down"), for: .normal)
    collapse.accessibilityLabel = LodyStrings.text("native.chat.camera.collapse")
    collapse.accessibilityIdentifier = "camera-collapse"
    collapse.addAction(UIAction { [weak self] _ in self?.onCollapse?() }, for: .touchUpInside)
    flash.accessibilityIdentifier = "camera-flash"
    flash.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      switch flashMode { case .auto: flashMode = .on; case .on: flashMode = .off; default: flashMode = .auto }
      updateFlash()
    }, for: .touchUpInside)
    updateFlash()
    shutter.setImage(UIImage(systemName: "circle.fill"), for: .normal)
    shutter.configuration?.preferredSymbolConfigurationForImage = .init(pointSize: 42)
    shutter.accessibilityLabel = LodyStrings.text("native.chat.composer.takePhoto")
    shutter.accessibilityIdentifier = "camera-shutter"
    shutter.addAction(UIAction { [weak self] _ in
      guard let self, ready, !busy else { return }
      busy = true
      render()
      onShutter?(flashMode, rotation?.videoRotationAngleForHorizonLevelCapture ?? 90)
    }, for: .touchUpInside)
    flip.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
    flip.accessibilityLabel = LodyStrings.text("native.chat.camera.flip")
    flip.accessibilityIdentifier = "camera-flip"
    flip.addAction(UIAction { [weak self] _ in
      self?.ready = false
      self?.render()
      self?.onFlip?()
    }, for: .touchUpInside)
    mode.text = LodyStrings.text("native.chat.camera.photo")
    mode.textColor = .white
    mode.font = .systemFont(ofSize: 13, weight: .semibold)
    mode.textAlignment = .center
    mode.backgroundColor = .black.withAlphaComponent(0.4)
    mode.layer.cornerRadius = 12
    mode.clipsToBounds = true
    retake.setImage(UIImage(systemName: "arrow.counterclockwise"), for: .normal)
    retake.accessibilityLabel = LodyStrings.text("native.chat.camera.retake")
    retake.accessibilityIdentifier = "camera-retake"
    retake.addAction(UIAction { [weak self] _ in self?.onRetake?() }, for: .touchUpInside)
    add.setImage(UIImage(systemName: "checkmark"), for: .normal)
    add.tintColor = .systemBlue
    add.accessibilityLabel = LodyStrings.text("native.chat.camera.add")
    add.accessibilityIdentifier = "camera-add"
    add.addAction(UIAction { [weak self] _ in self?.onAdd?() }, for: .touchUpInside)
    status.textColor = .white
    status.backgroundColor = .black.withAlphaComponent(0.65)
    status.layer.cornerRadius = 16
    status.clipsToBounds = true
    status.font = .preferredFont(forTextStyle: .body)
    status.numberOfLines = 0
    status.textAlignment = .center
    status.accessibilityIdentifier = "camera-status"
    retry.accessibilityIdentifier = "camera-retry"
    retry.addAction(UIAction { [weak self] _ in self?.onRetry?() }, for: .touchUpInside)
    focusRing.layer.borderWidth = 1.5
    focusRing.layer.borderColor = UIColor.white.cgColor
    focusRing.layer.cornerRadius = 8
    focusRing.alpha = 0
    focusRing.isUserInteractionEnabled = false
    for item in [collapse, flash, shutter, flip, mode, retake, add, status, retry, focusRing] { controls.addSubview(item) }
    controls.isUserInteractionEnabled = true
    // Only the actual controls intercept touches; focus taps elsewhere use this view.
    let focusTap = UITapGestureRecognizer(target: self, action: #selector(focus(_:)))
    focusTap.cancelsTouchesInView = false
    addGestureRecognizer(focusTap)
    render()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    preview.frame = bounds
    image.frame = bounds
    glyph.frame = CGRect(x: bounds.midX - 24, y: bounds.midY - 24, width: 48, height: 48)
    controls.frame = bounds
    let top = max(24, controlInsets.top + 8)
    let bottom = bounds.height - max(16, controlInsets.bottom + 12)
    collapse.frame = CGRect(x: 16 + controlInsets.left, y: top, width: 48, height: 48)
    flash.frame = CGRect(x: bounds.width - 64 - controlInsets.right, y: top, width: 48, height: 48)
    shutter.frame = CGRect(x: bounds.midX - 35, y: bottom - 70, width: 70, height: 70)
    flip.frame = CGRect(x: bounds.width - 72 - controlInsets.right, y: bottom - 59, width: 48, height: 48)
    mode.frame = CGRect(x: bounds.midX - 30, y: bottom - 104, width: 60, height: 24)
    retake.frame = CGRect(x: 20 + controlInsets.left, y: bottom - 50, width: 50, height: 50)
    add.frame = CGRect(x: bounds.width - 70 - controlInsets.right, y: bottom - 50, width: 50, height: 50)
    let messageHeight = min(110, status.sizeThatFits(CGSize(width: max(1, bounds.width - 64), height: 200)).height + 32)
    status.frame = CGRect(x: 24, y: bounds.midY - messageHeight / 2 - 22, width: bounds.width - 48, height: messageHeight)
    retry.frame = CGRect(x: bounds.midX - 24, y: status.frame.maxY + 12, width: 48, height: 48)
  }

  func setExpanded(_ value: Bool) {
    expanded = value
    backgroundColor = value ? .black : .secondarySystemBackground
    accessibilityIdentifier = value ? "camera-expanded" : "camera-tile-preview"
    controls.accessibilityElementsHidden = !value
    render()
  }

  func setReady(device: AVCaptureDevice?, canFlip: Bool) {
    ready = true
    busy = false
    status.text = nil
    rotationObservation = nil
    rotation = device.map { AVCaptureDevice.RotationCoordinator(device: $0, previewLayer: previewLayer) }
    rotationObservation = rotation?.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
      // RotationCoordinator delivers preview-angle observations on the main queue.
      MainActor.assumeIsolated {
        guard let connection = self?.previewLayer.connection else { return }
        let angle = coordinator.videoRotationAngleForHorizonLevelPreview
        if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
      }
    }
    flash.isEnabled = device?.hasFlash == true || ChatCameraCapture.fixture
    flip.isEnabled = canFlip
    render()
  }

  func showError(_ key: String, action: String? = "native.chat.camera.retry") {
    ready = false
    busy = false
    status.text = LodyStrings.text(key)
    retry.accessibilityLabel = action.map { LodyStrings.text($0) }
    retry.setImage(UIImage(systemName: action == "native.chat.camera.retry" ? "arrow.clockwise" : "gearshape"), for: .normal)
    render()
    setNeedsLayout()
  }

  func setPhoto(_ photo: ChatAttachment?) {
    reviewing = photo != nil
    ready = false
    image.contentMode = reviewing ? .scaleAspectFit : .scaleAspectFill
    busy = false
    status.text = nil
    image.image = photo.flatMap { UIImage(contentsOfFile: $0.url.path) }
    if photo == nil && ChatCameraCapture.fixture { image.image = ChatCameraCapture.fixtureImage() }
    render()
  }

  private func updateFlash() {
    let key: String
    switch flashMode { case .auto: key = "auto"; case .on: key = "on"; default: key = "off" }
    let symbol: String
    switch flashMode { case .auto: symbol = "bolt.badge.a"; case .on: symbol = "bolt.fill"; default: symbol = "bolt.slash" }
    flash.setImage(UIImage(systemName: symbol), for: .normal)
    flash.accessibilityLabel = LodyStrings.text("native.chat.camera.flash") + ": " + LodyStrings.text("native.chat.camera.flash." + key)
  }

  private func render() {
    glyph.alpha = expanded ? 0 : 1
    controls.alpha = expanded ? 1 : 0
    shutter.isHidden = reviewing
    mode.isHidden = reviewing
    flip.isHidden = reviewing
    flash.isHidden = reviewing
    retake.isHidden = !reviewing
    add.isHidden = !reviewing
    status.isHidden = status.text == nil || reviewing
    retry.isHidden = status.isHidden || retry.accessibilityLabel == nil
    shutter.isEnabled = ready && !busy && !reviewing
    shutter.alpha = shutter.isEnabled ? 1 : 0.4
    collapse.isEnabled = !busy
    flip.isEnabled = flip.isEnabled && !busy
  }

  @objc private func focus(_ gesture: UITapGestureRecognizer) {
    guard expanded, ready, !reviewing, !busy else { return }
    let point = gesture.location(in: controls)
    guard ![collapse, flash, shutter, flip, retry, retake, add].contains(where: { !$0.isHidden && $0.frame.contains(point) }) else { return }
    onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint: gesture.location(in: preview)))
    focusRing.layer.removeAllAnimations()
    focusRing.frame = CGRect(x: point.x - 30, y: point.y - 30, width: 60, height: 60)
    focusRing.alpha = 1
    UIView.animate(withDuration: 0.3, delay: 0.6, options: [.beginFromCurrentState]) { self.focusRing.alpha = 0 }
  }
}
