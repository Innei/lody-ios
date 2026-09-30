import ExpoModulesCore
import UIKit

final class LodySimulatorView: ExpoView {
  private struct Source: Decodable, Equatable {
    let url: String
    let udid: String
  }

  private struct Command: Decodable {
    let token: Int
    let action: String
  }

  private enum Mode {
    case idle
    case single(edge: String?)
    case double
  }

  private static let buttons: Set<String> = ["home", "app-switcher", "power", "volume-up", "volume-down", "action"]
  private static let orientations = [0: "portrait", 90: "landscape-left", 270: "landscape-right"]

  private var source: Source?
  private var device: SimulatorDeviceView?
  private let status = UILabel()
  private let decoder = SimulatorStreamDecoder()
  private var session: URLSession?
  private var socket: URLSessionWebSocketTask?
  private var receiving: Task<Void, Never>?
  private var loading: Task<Void, Never>?
  private var fingers: [UITouch] = []
  private var mode = Mode.idle
  private var rotation = 0
  private var lastCommand = 0

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    isMultipleTouchEnabled = true
    status.textColor = .secondaryLabel
    status.font = .preferredFont(forTextStyle: .subheadline)
    status.adjustsFontForContentSizeCategory = true
    addSubview(status)
    decoder.onOutput = { [weak self] output in self?.show(output) }
  }

  func setSource(_ json: String) {
    guard let next = try? JSONDecoder().decode(Source.self, from: Data(json.utf8)), next != source else { return }
    disconnect()
    loading?.cancel()
    device?.removeFromSuperview()
    device = nil
    source = next
    rotation = 0
    setStatus("native.simulator.connecting")
    guard let url = URL(string: next.url) else { return setStatus("native.simulator.unavailable") }
    loading = Task { [weak self] in
      let definition = await SimulatorRemote.definition(url, udid: next.udid)
      guard let self, !Task.isCancelled, self.source == next else { return }
      guard let definition else { return self.setStatus("native.simulator.unavailable") }
      self.install(definition)
      if self.window != nil { self.connect() }
    }
  }

  func setCommand(_ json: String) {
    guard let command = try? JSONDecoder().decode(Command.self, from: Data(json.utf8)),
          command.token > lastCommand else { return }
    lastCommand = command.token
    perform(command.action)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      disconnect()
    } else if device != nil, socket == nil {
      connect()
    }
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let area = bounds.inset(by: UIEdgeInsets(
      top: safeAreaInsets.top + 16, left: safeAreaInsets.left + 16,
      bottom: safeAreaInsets.bottom + 16, right: safeAreaInsets.right + 16))
    status.sizeToFit()
    status.center = CGPoint(x: area.midX, y: area.midY)
    guard let device, area.width > 0, area.height > 0 else { return }
    let canvas = device.canvasSize
    let turned = rotation % 180 != 0
    let fitted = CGSize(width: turned ? canvas.height : canvas.width, height: turned ? canvas.width : canvas.height)
    let scale = min(area.width / fitted.width, area.height / fitted.height)
    device.bounds = CGRect(origin: .zero, size: CGSize(width: canvas.width * scale, height: canvas.height * scale))
    device.center = CGPoint(x: area.midX, y: area.midY)
    device.transform = CGAffineTransform(rotationAngle: CGFloat(rotation) * .pi / 180)
    bringSubviewToFront(status)
  }

  private func install(_ definition: SimulatorDefinition) {
    let device = SimulatorDeviceView(definition: definition)
    device.onButton = { [weak self] envelope in self?.send(envelope) }
    device.display.accessibilityIdentifier = "simulator-stream"
    insertSubview(device, belowSubview: status)
    self.device = device
    setNeedsLayout()
  }

  private func connect() {
    guard let source, let url = URL(string: source.url),
          let stream = SimulatorRemote.endpoint(
            url, path: "/simulators/\(source.udid)/stream",
            query: [URLQueryItem(name: "format", value: "avcc"), URLQueryItem(name: "version", value: "v2")],
            scheme: "wss") else { return }
    let session = URLSession(configuration: .ephemeral)
    let task = session.webSocketTask(with: stream)
    task.maximumMessageSize = 16 * 1024 * 1024
    self.session = session
    socket = task
    task.resume()
    receiving = Task { [weak self] in
      while !Task.isCancelled {
        let message: URLSessionWebSocketTask.Message
        do { message = try await task.receive() } catch {
          if self?.socket === task { self?.setStatus("native.simulator.disconnected") }
          return
        }
        guard let self else { return }
        if case .data(let data) = message { self.decoder.handle(data) }
      }
    }
  }

  private func disconnect() {
    receiving?.cancel()
    receiving = nil
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
    session?.invalidateAndCancel()
    session = nil
  }

  private func show(_ output: SimulatorStreamDecoder.Output) {
    status.isHidden = true
    guard let device else { return }
    switch output {
    case .seed(let image):
      device.seed.image = image
    case .frame(let sample):
      if device.display.displayLayer.status == .failed { device.display.displayLayer.flush() }
      device.display.displayLayer.enqueue(sample)
    }
  }

  private func setStatus(_ key: String) {
    status.text = LodyStrings.text(key)
    status.isHidden = false
    setNeedsLayout()
  }

  private func perform(_ action: String) {
    guard let source, let url = URL(string: source.url) else { return }
    if Self.buttons.contains(action) { return send(["type": "button", "button": action]) }
    switch action {
    case "rotate-left", "rotate-right":
      let step = action == "rotate-right" ? 90 : 270
      let next = (rotation + step) % 360
      guard let value = Self.orientations[next] else { return }
      rotation = next
      setNeedsLayout()
      UIView.animate(withDuration: 0.3) { self.layoutIfNeeded() }
      Task { await SimulatorRemote.post(url, path: "/simulators/\(source.udid)/orientation", query: [URLQueryItem(name: "value", value: value)]) }
    case "shake":
      Task { await SimulatorRemote.post(url, path: "/simulators/\(source.udid)/shake") }
    case "screenshot":
      Task { [weak self] in
        guard let image = await SimulatorRemote.screenshot(url, udid: source.udid), let self,
              let controller = self.owningController else { return }
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = self
        controller.present(sheet, animated: true)
      }
    default:
      break
    }
  }

  private var owningController: UIViewController? {
    var responder: UIResponder? = self
    while let current = responder {
      if let controller = current as? UIViewController { return controller }
      responder = current.next
    }
    return nil
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let device else { return }
    let before = fingers.count
    for touch in touches where fingers.count < 2 && !fingers.contains(touch) { fingers.append(touch) }
    if before == 0, fingers.count == 1 {
      guard device.display.bounds.contains(fingers[0].location(in: device.display)) else { return }
      let point = location(fingers[0])
      let edge = edge(point)
      mode = .single(edge: edge)
      touch("touch1-down", [point], edge: edge)
    } else if fingers.count == 2, before < 2 {
      if case .single(let edge) = mode { touch("touch1-up", [location(fingers[0])], edge: edge) }
      mode = .double
      touch("touch2-down", fingers.map(location))
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    switch mode {
    case .single(let edge): touch("touch1-move", [location(fingers[0])], edge: edge)
    case .double: touch("touch2-move", fingers.map(location))
    case .idle: break
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

  private func lift(_ touches: Set<UITouch>) {
    guard fingers.contains(where: touches.contains) else { return }
    switch mode {
    case .single(let edge): touch("touch1-up", [location(fingers[0])], edge: edge)
    case .double: touch("touch2-up", fingers.map(location))
    case .idle: break
    }
    mode = .idle
    fingers.removeAll(where: touches.contains)
  }

  /// `location(in:)` undoes the rotation transform, so points stay in the
  /// simulator's portrait framebuffer space that baguette expects.
  private func location(_ touch: UITouch) -> CGPoint {
    guard let device else { return .zero }
    let point = touch.location(in: device.display)
    let bounds = device.display.bounds
    let size = device.definition.screen.size
    guard bounds.width > 0, bounds.height > 0 else { return .zero }
    return CGPoint(
      x: min(max(point.x / bounds.width, 0), 1) * size.width,
      y: min(max(point.y / bounds.height, 0), 1) * size.height)
  }

  /// baguette treats the hint as a possible home-indicator or notification swipe
  /// and still lands a plain tap there, using the same bands as its web client.
  private func edge(_ point: CGPoint) -> String? {
    let y = point.y / max(device?.definition.screen.height ?? 1, 1)
    if y >= 0.85 { return "bottom" }
    if y <= 0.15 { return "top" }
    return nil
  }

  private func touch(_ type: String, _ points: [CGPoint], edge: String? = nil) {
    guard let size = device?.definition.screen.size else { return }
    var envelope: [String: Any] = ["type": type, "width": size.width, "height": size.height]
    if points.count == 1 {
      envelope["x"] = points[0].x
      envelope["y"] = points[0].y
      if let edge { envelope["edge"] = edge }
    } else if points.count == 2 {
      envelope["x1"] = points[0].x
      envelope["y1"] = points[0].y
      envelope["x2"] = points[1].x
      envelope["y2"] = points[1].y
    }
    send(envelope)
  }

  private func send(_ envelope: [String: Any]) {
    guard let socket, let data = try? JSONSerialization.data(withJSONObject: envelope),
          let text = String(data: data, encoding: .utf8) else { return }
    socket.send(.string(text)) { _ in }
  }
}
