import ExpoModulesCore
import UIKit

/// Full-screen host borrows the chat-owned renderer, including its live decoder.
final class LodySimulatorView: ExpoView {
  private var stream: SimulatorStreamView?
  private var lastCommand = 0

  func setSource(_ json: String) {
    let next = SimulatorStreamView.shared(json)
    guard next !== stream else { return }
    returnToPreview()
    stream = next
    if window != nil { attach() }
  }

  func setCommand(_ json: String) {
    struct Command: Decodable { let token: Int; let action: String }
    guard let command = try? JSONDecoder().decode(Command.self, from: Data(json.utf8)),
          command.token > lastCommand else { return }
    lastCommand = command.token
    stream?.perform(command.action)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { returnToPreview() } else { attach() }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if stream?.superview === self { stream?.frame = bounds }
  }

  private func attach() {
    guard let stream else { return }
    stream.fullscreen = self
    stream.compact = false
    addSubview(stream)
    stream.frame = bounds
    stream.preview?.isHidden = true
  }

  private func returnToPreview() {
    guard let stream, stream.fullscreen === self else { return }
    stream.fullscreen = nil
    stream.preview?.attach()
  }
}
