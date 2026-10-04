import Foundation
@preconcurrency import WebRTC

func chunk(_ bytes: Data, total: Int, offset: Int) -> Data {
  var result = Data()
  withUnsafeBytes(of: UInt32(total).bigEndian) { result.append(contentsOf: $0) }
  withUnsafeBytes(of: UInt32(offset).bigEndian) { result.append(contentsOf: $0) }
  result.append(bytes)
  return result
}

// Real DTLS/SCTP pair; only HTTP signaling is injected. The framing/labels and
// envelopes match LodyAI/Lody e135cdb5. This is not a live TURN/werift acceptance.
@MainActor final class Gateway: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate {
  static var current: Gateway?
  static let frame = Data((0..<40_000).map { UInt8($0 % 251) })
  let factory = RTCPeerConnectionFactory()
  var peer: RTCPeerConnection!
  var channels: [String: RTCDataChannel] = [:]
  var gathering: CheckedContinuation<Void, Never>?
  var ready = false
  var framesSent = false
  var commands = 0

  override init() {
    super.init()
    let config = RTCConfiguration()
    config.iceServers = []
    peer = factory.peerConnection(with: config,
      constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: self)!
  }

  func answer(_ sdp: String) async throws -> String {
    try await peer.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp))
    let answer = try await peer.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
    try await peer.setLocalDescription(answer)
    if peer.iceGatheringState != .complete {
      await withCheckedContinuation { gathering = $0 }
    }
    return peer.localDescription!.sdp
  }

  func send(_ object: [String: Any]) {
    precondition(channels["control"]!.sendData(RTCDataBuffer(
      data: try! JSONSerialization.data(withJSONObject: object), isBinary: false)))
  }

  func opened() {
    guard !ready, channels["media"]?.readyState == .open, channels["control"]?.readyState == .open else { return }
    ready = true
    send(["type": "rtc-ready"])
  }

  func receive(_ data: Data) {
    let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    if object["type"] as? String == "heartbeat", !framesSent {
      framesSent = true
      for offset in stride(from: 0, to: Self.frame.count, by: 12_000) {
        let part = Self.frame.subdata(in: offset..<min(offset + 12_000, Self.frame.count))
        precondition(channels["media"]!.sendData(RTCDataBuffer(
          data: chunk(part, total: Self.frame.count, offset: offset), isBinary: true)))
      }
    }
    if let id = object["requestId"] as? String {
      commands += 1
      let control = object["control"] as! [String: String]
      if control["button"] == "lock" {
        // It executed, but its reply was lost. Client must not replay on fallback.
        peer.close()
      } else {
        send(["type": "rtc-control-result", "requestId": id, "success": true])
      }
    }
  }

  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
  nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
    if newState == .complete {
      DispatchQueue.main.async { [weak self] in self?.gathering?.resume(); self?.gathering = nil }
    }
  }
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.channels[dataChannel.label] = dataChannel
      dataChannel.delegate = self
      self.opened()
    }
  }
  nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
    DispatchQueue.main.async { [weak self] in self?.opened() }
  }
  nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
    let data = buffer.data
    DispatchQueue.main.async { [weak self] in self?.receive(data) }
  }
}

final class Signaling: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.path.hasPrefix("/native/") == true && ["rtc", "rtc-config"].contains(request.url!.lastPathComponent)
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let request = request
    precondition(request.url!.query == "token=synthetic")
    precondition(request.value(forHTTPHeaderField: "Origin") == "http://127.0.0.1:\(request.url!.port!)")
    var body = request.httpBody ?? Data()
    if let input = request.httpBodyStream {
      input.open()
      defer { input.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while input.hasBytesAvailable {
        let count = input.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        body.append(contentsOf: buffer.prefix(count))
      }
    }
    let capturedBody = body
    Task { @MainActor in
      let result: [String: Any]
      if request.url!.lastPathComponent == "rtc-config" {
        result = ["iceServers": []]
      } else {
        let offer = try! JSONSerialization.jsonObject(with: capturedBody) as! [String: String]
        precondition(offer["codec"] == "h264")
        let gateway = Gateway()
        Gateway.current = gateway
        result = ["sdp": try! await gateway.answer(offer["sdp"]!)]
      }
      self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
        httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
      self.client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: result))
      self.client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() {}
}

@MainActor func verify() async throws {
  // Guard corruption and allocation boundaries independently of RTC's happy path.
  var assembler = SimulatorRTCFrame()
  let partial = try assembler.append(chunk(Data([1, 2]), total: 4, offset: 0))
  let complete = try assembler.append(chunk(Data([3, 4]), total: 4, offset: 2))
  precondition(partial == nil && complete == Data([1, 2, 3, 4]))
  for bad in [chunk(Data([1]), total: 17 * 1024 * 1024, offset: 0),
              chunk(Data([1]), total: 2, offset: 1), Data(repeating: 0, count: 16 * 1024 + 1)] {
    do { _ = try assembler.append(bad); preconditionFailure("Accepted corrupt frame") } catch {}
  }
  _ = try assembler.append(chunk(Data([1]), total: 3, offset: 0))
  do { _ = try assembler.append(chunk(Data([2]), total: 4, offset: 1)); preconditionFailure("Accepted changed total") } catch {}
  print("PASS bounded frame reassembly and corrupt frame rejection")

  let base = ProcessInfo.processInfo.environment["LODY_SIMULATOR_TEST_URL"]!
  func make(_ mode: String) -> SimulatorTransport {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Signaling.self]
    return SimulatorTransport(viewer: URL(string: "\(base)/\(mode)/?token=synthetic")!, h264: true, configuration: configuration)
  }
  let transport = make("native")
  var fallbacks = 0
  transport.onFallback = { fallbacks += 1 }
  let (messages, continuation) = AsyncStream<URLSessionWebSocketTask.Message>.makeStream()
  transport.onMessage = { continuation.yield($0) }
  transport.onOpen = { transport.send(["type": "heartbeat"]) }
  transport.onClose = { code in preconditionFailure("Unexpected close \(code)") }
  transport.start(preferRTC: true)
  var iterator = messages.makeAsyncIterator()
  guard case .data(let frame) = await iterator.next() else { preconditionFailure("No RTC frame") }
  precondition(frame == Gateway.frame && transport.mode == .webRTC && fallbacks == 0)
  let success = await transport.perform(operationId: "synthetic-operation", control: ["kind": "button", "button": "home"])
  precondition(success)
  print("PASS real WebRTC frames and acknowledged control")

  let uncertain = await transport.perform(operationId: "synthetic-operation", control: ["kind": "button", "button": "lock"])
  precondition(!uncertain)
  guard case .string("fallback-ready") = await iterator.next() else { preconditionFailure("No WebSocket fallback") }
  precondition(fallbacks == 1 && transport.mode == .webSocket && Gateway.current!.commands == 2)
  // Echo is an ordering barrier: fallback has accepted input before inspecting its receipts.
  guard case .string = await iterator.next() else { preconditionFailure("No fallback heartbeat") }
  transport.close()
  continuation.finish()
  transport.onOpen = nil
  print("PASS established RTC loss falls back without replaying uncertain control")

  for mode in ["unsupported", "malformed", "redirect"] {
    let connection = make(mode)
    let (events, output) = AsyncStream<URLSessionWebSocketTask.Message>.makeStream()
    var switched = 0
    connection.onFallback = { switched += 1 }
    connection.onMessage = { output.yield($0) }
    connection.start(preferRTC: true)
    var next = events.makeAsyncIterator()
    guard case .string("fallback-ready") = await next.next() else { preconditionFailure("No \(mode) fallback") }
    precondition(switched == 1 && connection.mode == .webSocket)
    connection.close()
    output.finish()
    print("PASS \(mode) signaling uses WebSocket")
  }
  let stopped = make("hanging")
  stopped.onFallback = { preconditionFailure("Stop opened a fallback connection") }
  stopped.onOpen = { preconditionFailure("Stop opened a connection") }
  stopped.start(preferRTC: true)
  _ = try await URLSession.shared.data(from: URL(string: "\(base)/await-hanging")!)
  stopped.close()
  stopped.send(["type": "touch1-down"])
  let rejected = await stopped.perform(operationId: "synthetic-operation", control: ["kind": "button", "button": "home"])
  precondition(!rejected && stopped.mode == .closed)

  let (data, _) = try await URLSession.shared.data(from: URL(string: "\(base)/stats")!)
  let stats = try JSONSerialization.jsonObject(with: data) as! [String: Any]
  precondition((stats["controls"] as! [String]).isEmpty, "Uncertain control replayed over HTTP")
  precondition(stats["redirects"] as! Int == 0, "Capability followed redirect")
  precondition(stats["hanging"] as! Int == 1, "Negotiation was not in flight")
  precondition(!(stats["sockets"] as! [String]).contains("/hanging/stream"))
  precondition((stats["inputs"] as! [[String: Any]]).allSatisfy { $0["type"] as? String == "heartbeat" })
  print("PASS close cancels negotiation and input; no capability redirects or input replay")
}

Task { @MainActor in
  do { try await verify(); print("Simulator transport checks passed"); exit(0) }
  catch { print("Simulator transport check failed: \(error)"); exit(1) }
}
dispatchMain()
