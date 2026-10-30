import AppKit
import LodyData

@MainActor
final class MacPlaceholderController: NSViewController {
  private let text: String

  init(text: String) {
    self.text = text
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { nil }

  override func loadView() {
    let label = NSTextField(labelWithString: text)
    label.textColor = .secondaryLabelColor
    label.translatesAutoresizingMaskIntoConstraints = false
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    root.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: root.centerYAnchor),
    ])
    view = root
  }
}
