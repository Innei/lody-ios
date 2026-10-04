import Foundation
@preconcurrency import WebRTC

/// One native, data-only peer for the CLI's authenticated simulator gateway.
/// No audio/video tracks, WebView, credentials in documents, or input replay.
@MainActor final class SimulatorRTC: NSObject {
  private static let factory: RTCPeerConnectionFactory = {
    RTCInitializeSSL()
    return RTCPeerConnectionFactory()
  }()

  var onOpen: (() -> Void)?
  var onMessage: ((URLSessionWebSocketTask.Message) -> Void)?
  var onFailure: ((Int) -> Void)?
  private(set) var isOpen = false
  private var closed = false
  private var localDescriptionSet = false
  private var offerSent = false
  private var peer: RTCPeerConnection?
  private var media: RTCDataChannel?
  private var control: RTCDataChannel?
  private var frames = SimulatorRTCFrame()
  private var signaling: Task<Void, Never>?
  private var deadline: Task<Void, Never>?
  private var pendingControl: (id: String, finish: (Bool) -> Void)?
  private var controlDeadline: Task<Void, Never>?
  private let viewer: URL
  private let h264: Bool
  private let session: URLSession

  init(viewer: URL, h264: Bool, session: URLSession) {
    self.viewer = viewer
    self.h264 = h264
    self.session = session
  }

  func start() {
    deadline = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(12)) } catch { return }
      self?.fail()
    }
    signaling = Task { [weak self] in
      guard let self, !closed else { return }
      do {
        let data = try await read("rtc-config")
        let config = try JSONDecoder().decode(IceConfiguration.self, from: data)
        guard !closed else { return }
        let rtc = RTCConfiguration()
        rtc.sdpSemantics = .unifiedPlan
        rtc.iceServers = try config.servers()
        guard let peer = Self.factory.peerConnection(
          with: rtc, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil),
          delegate: self) else { return fail() }
        self.peer = peer
        let options = RTCDataChannelConfiguration()
        options.isOrdered = true
        media = peer.dataChannel(forLabel: "media", configuration: options)
        control = peer.dataChannel(forLabel: "control", configuration: options)
        guard media != nil, control != nil else { return fail() }
        media?.delegate = self
        control?.delegate = self
        let description = try await peer.offer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        guard !closed else { return }
        try await peer.setLocalDescription(description)
        guard !closed else { return }
        localDescriptionSet = true
        exchangeOffer()
      } catch { fail() }
    }
  }

  private func exchangeOffer() {
    guard !closed, localDescriptionSet, !offerSent, let peer, let sdp = peer.localDescription?.sdp,
          peer.iceGatheringState == .complete || sdp.contains(" typ relay ") else { return }
    guard sdp.utf8.count <= 64 * 1024 else { return fail() }
    offerSent = true
    signaling = Task { [weak self] in
      guard let self else { return }
      do {
        let data = try await read("rtc", body: ["sdp": sdp, "codec": h264 ? "h264" : "mjpeg"])
        struct Answer: Decodable { let sdp: String }
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        guard !closed else { return }
        guard !answer.sdp.isEmpty, answer.sdp.utf8.count <= 64 * 1024 else { return fail() }
        try await peer.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer.sdp))
      } catch { fail() }
    }
  }

  /// Stream responses incrementally so a remote response cannot allocate unbounded memory.
  private func read(_ name: String, body: [String: String]? = nil) async throws -> Data {
    guard let address = SimulatorRemote.endpoint(viewer, name) else { throw URLError(.badURL) }
    var request = SimulatorRemote.request(viewer, address, timeout: 12)
    if let body {
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    let (bytes, response) = try await session.bytes(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 70 * 1024 else { throw URLError(.dataLengthExceedsMaximum) }
      data.append(byte)
    }
    try Task.checkCancellation()
    return data
  }

  func send(_ text: String) {
    guard !closed, isOpen, let control, control.readyState == .open else { return }
    guard text.utf8.count <= 128 * 1024, control.bufferedAmount <= 128 * 1024,
          control.sendData(RTCDataBuffer(data: Data(text.utf8), isBinary: false)) else { return fail() }
  }

  func requestControl(operationId: String, control: [String: String]) async -> Bool {
    guard !closed, isOpen, pendingControl == nil else { return false }
    let id = UUID().uuidString
    guard let body = try? JSONSerialization.data(withJSONObject: [
      "operationId": operationId, "requestId": id, "control": control,
    ]), let text = String(data: body, encoding: .utf8) else { return false }
    return await withCheckedContinuation { continuation in
      pendingControl = (id, { continuation.resume(returning: $0) })
      controlDeadline = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(12)) } catch { return }
        self?.finishControl(false)
      }
      send(text)
    }
  }

  private func finishControl(_ success: Bool) {
    let pending = pendingControl
    pendingControl = nil
    controlDeadline?.cancel()
    controlDeadline = nil
    pending?.finish(success)
  }

  func close() {
    guard !closed else { return }
    closed = true
    isOpen = false
    signaling?.cancel()
    signaling = nil
    deadline?.cancel()
    deadline = nil
    finishControl(false)
    frames = SimulatorRTCFrame()
    media?.delegate = nil
    control?.delegate = nil
    peer?.delegate = nil
    media?.close()
    control?.close()
    peer?.close()
    media = nil
    control = nil
    peer = nil
  }

  private func fail(_ code: Int = 1000) {
    guard !closed else { return }
    close()
    onFailure?(code)
  }

  private func receive(_ data: Data, binary: Bool, label: String) {
    guard !closed else { return }
    if label == "media" {
      guard isOpen, binary else { return fail() }
      do {
        if let frame = try frames.append(data) { onMessage?(.data(frame)) }
      } catch { fail() }
      return
    }
    guard !binary, data.count <= 128 * 1024,
          let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return fail() }
    switch message["type"] as? String {
    case "rtc-ready":
      guard !isOpen, media?.readyState == .open, control?.readyState == .open else { return fail() }
      isOpen = true
      deadline?.cancel()
      deadline = nil
      onOpen?()
    case "rtc-close":
      fail(message["code"] as? Int == 4002 ? 4002 : 1000)
    case "rtc-control-result":
      if message["requestId"] as? String == pendingControl?.id {
        finishControl(message["success"] as? Bool == true)
      }
    default:
      if isOpen, let text = String(data: data, encoding: .utf8) { onMessage?(.string(text)) }
    }
  }

  private struct IceConfiguration: Decodable {
    struct Server: Decodable { let urls: [String]; let username: String?; let credential: String? }
    let iceServers: [Server]
    func servers() throws -> [RTCIceServer] {
      guard iceServers.count <= 8 else { throw URLError(.badServerResponse) }
      return try iceServers.map { server in
        guard !server.urls.isEmpty, server.urls.count <= 8,
              server.urls.allSatisfy({ url in
                url.utf8.count <= 512 && ["stun:", "turn:", "turns:"].contains(where: url.hasPrefix)
              }), (server.username?.utf8.count ?? 0) <= 1024,
              (server.credential?.utf8.count ?? 0) <= 4096 else { throw URLError(.badServerResponse) }
        return RTCIceServer(urlStrings: server.urls, username: server.username, credential: server.credential)
      }
    }
  }
}

extension SimulatorRTC: RTCPeerConnectionDelegate, RTCDataChannelDelegate {
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
  nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
    if [.failed, .disconnected, .closed].contains(newState) {
      DispatchQueue.main.async { [weak self] in self?.fail() }
    }
  }
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
    DispatchQueue.main.async { [weak self] in self?.exchangeOffer() }
  }
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
    DispatchQueue.main.async { [weak self] in self?.exchangeOffer() }
  }
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
  nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
    // Both channels must be created by us; reject unsolicited remote channels.
    DispatchQueue.main.async { [weak self] in self?.fail() }
  }
  nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
    if dataChannel.readyState == .closed {
      DispatchQueue.main.async { [weak self] in self?.fail() }
    }
  }
  nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
    let data = buffer.data
    let binary = buffer.isBinary
    let label = dataChannel.label
    DispatchQueue.main.async { [weak self] in self?.receive(data, binary: binary, label: label) }
  }
}
