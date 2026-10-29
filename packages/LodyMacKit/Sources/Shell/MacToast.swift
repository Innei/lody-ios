import AppKit

@MainActor
enum MacToast {
  static func show(_ message: String, kind: String, in window: NSWindow?) {
    guard let content = window?.contentView else { return }
    content.subviews.filter { $0.accessibilityIdentifier() == "toast" }.forEach { $0.removeFromSuperview() }
    let banner = NSVisualEffectView()
    banner.material = .popover
    banner.blendingMode = .withinWindow
    banner.state = .active
    banner.wantsLayer = true
    banner.layer?.cornerRadius = 10
    let symbol = kind == "error" ? "exclamationmark.triangle.fill" : "info.circle.fill"
    let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
    icon.contentTintColor = kind == "error" ? .systemOrange : .secondaryLabelColor
    let label = NSTextField(wrappingLabelWithString: message)
    label.font = .systemFont(ofSize: 13)
    let stack = NSStackView(views: [icon, label])
    stack.spacing = 8
    stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    stack.translatesAutoresizingMaskIntoConstraints = false
    banner.addSubview(stack)
    banner.translatesAutoresizingMaskIntoConstraints = false
    banner.setAccessibilityIdentifier("toast")
    content.addSubview(banner)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: banner.topAnchor),
      stack.bottomAnchor.constraint(equalTo: banner.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: banner.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: banner.trailingAnchor),
      banner.centerXAnchor.constraint(equalTo: content.centerXAnchor),
      banner.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
      banner.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -48),
    ])
    NSAccessibility.post(element: banner, notification: .announcementRequested, userInfo: [
      .announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue,
    ])
    Task { [weak banner] in
      try? await Task.sleep(for: .seconds(4))
      banner?.removeFromSuperview()
    }
  }
}
