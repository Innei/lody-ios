import AppKit

@MainActor
final class MacActionButton: NSButton {
  private let invoke: () -> Void
  init(title: String, action: @escaping () -> Void) {
    invoke = action
    super.init(frame: .zero)
    self.title = title
    bezelStyle = .rounded
    target = self
    self.action = #selector(pressed)
  }
  required init?(coder: NSCoder) { nil }
  @objc private func pressed() { invoke() }
}
