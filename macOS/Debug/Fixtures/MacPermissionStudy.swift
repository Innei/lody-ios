#if DEBUG
import AppKit
import LodyData

/// Native design studies only; the production permission flow remains unchanged until a direction is chosen.
@MainActor
enum MacPermissionStudy {
  static func windows(_ variant: String) -> [NSWindow] {
    let windows = MacFixtures.workspaceWindow(sessionId: "s-mac", shell: true)
    guard let window = windows.first else { return windows }
    window.setContentSize(NSSize(width: 1100, height: 720))
    window.layoutIfNeeded()
    guard let composer = descendants(window.contentView).compactMap({ $0 as? MacComposerView }).first,
      let parent = composer.superview else { return windows }
    composer.widthAnchor.constraint(equalToConstant: 748).isActive = true
    composer.input.string = "Keep the native controls and align the sidebar rows."
    composer.input.isEditable = false
    composer.input.isSelectable = false
    composer.input.setAccessibilityEnabled(false)
    for control in descendants(composer).compactMap({ $0 as? NSControl }) { control.isEnabled = false }
    composer.alphaValue = 0.35
    let panel = NSVisualEffectView()
    panel.material = .popover
    panel.blendingMode = .withinWindow
    panel.state = .active
    panel.wantsLayer = true
    panel.layer?.cornerRadius = 20
    panel.layer?.masksToBounds = true
    panel.translatesAutoresizingMaskIntoConstraints = false
    let title = NSTextField(labelWithString: "Allow this file edit?")
    title.font = .preferredFont(forTextStyle: .headline)
    let detail = NSTextField(wrappingLabelWithString: "Lody is waiting for your permission to continue.")
    detail.font = .preferredFont(forTextStyle: .body)
    detail.textColor = .secondaryLabelColor
    let file = NSTextField(labelWithString: "SidebarViewController.swift")
    file.font = .monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    let folder = NSTextField(labelWithString: "lody-ios · mac-client")
    folder.font = .preferredFont(forTextStyle: .caption1)
    folder.textColor = .secondaryLabelColor
    let allow = NSButton(title: "Allow", target: nil, action: nil)
    allow.bezelStyle = .rounded
    allow.bezelColor = .lodyAccent
    allow.setAccessibilityIdentifier("permission-study-allow")
    let deny = NSButton(title: "Deny", target: nil, action: nil)
    deny.bezelStyle = .rounded
    let actions = NSStackView(views: [deny, allow])
    actions.spacing = 8
    let stack = NSStackView(views: [title, detail, file, folder, actions])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    panel.addSubview(stack)
    parent.addSubview(panel, positioned: .above, relativeTo: composer)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -20),
      stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 20),
      stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -20),
      actions.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
      panel.centerXAnchor.constraint(equalTo: composer.centerXAnchor),
    ])
    if variant == "a" {
      NSLayoutConstraint.activate([
        panel.widthAnchor.constraint(equalTo: composer.widthAnchor),
        panel.bottomAnchor.constraint(equalTo: composer.bottomAnchor),
      ])
    } else {
      NSLayoutConstraint.activate([
        panel.widthAnchor.constraint(equalToConstant: 460),
        panel.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -12),
      ])
    }
    window.layoutIfNeeded()
    return windows
  }

  private static func descendants(_ view: NSView?) -> [NSView] {
    guard let view else { return [] }
    return [view] + view.subviews.flatMap { descendants($0) }
  }
}
#endif
