#if DEBUG
import AppKit

/// Offline, native material studies for the artboard. Production chrome is unchanged.
@MainActor
enum MacChromeStudy {
  static let variants = ["a", "b", "c"]

  static func windows(footer: String? = nil, composer: String? = nil, newSession: Bool = false) -> [NSWindow] {
    let windows = MacFixtures.workspaceWindow(sessionId: newSession ? nil : "s-mac", shell: true)
    guard let window = windows.first, let controller = window.windowController as? MainWindowController,
          let sidebar = controller.workspace?.sidebar else { return windows }
    window.setContentSize(NSSize(width: 1100, height: 720))
    window.layoutIfNeeded()
    sidebar.bottomAccessory.automaticallyAppliesContentInsets = false
    sidebar.bottomAccessory.view = footerView(footer ?? "a")
    if let composer, let original = descendants(window.contentView).compactMap({ $0 as? MacComposerView }).first {
      // Studies use one fixed window and the same column for every variant.
      // A glass view otherwise sizes itself to its content's intrinsic width.
      original.widthAnchor.constraint(equalToConstant: newSession ? 680 : 748).isActive = true
      original.subviews.forEach { $0.removeFromSuperview() }
      let study = composerView(composer, newSession: newSession)
      study.translatesAutoresizingMaskIntoConstraints = false
      original.addSubview(study)
      NSLayoutConstraint.activate([
        study.leadingAnchor.constraint(equalTo: original.leadingAnchor),
        study.trailingAnchor.constraint(equalTo: original.trailingAnchor),
        study.topAnchor.constraint(equalTo: original.topAnchor),
        study.bottomAnchor.constraint(equalTo: original.bottomAnchor),
      ])
    }
    window.layoutIfNeeded()
    return windows
  }

  private static func descendants(_ view: NSView?) -> [NSView] {
    guard let view else { return [] }
    return [view] + view.subviews.flatMap { descendants($0) }
  }

  private static func stack(_ views: [NSView], vertical: Bool = false, gap: CGFloat = 8, inset: CGFloat = 0) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = vertical ? .vertical : .horizontal
    stack.alignment = vertical ? .leading : .centerY
    stack.spacing = gap
    stack.edgeInsets = NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
    stack.setHuggingPriority(.init(1), for: .horizontal)
    stack.setContentHuggingPriority(.init(1), for: .horizontal)
    return stack
  }

  private static func spacer() -> NSView {
    let view = NSView()
    view.setContentHuggingPriority(.init(1), for: .horizontal)
    return view
  }

  private static func icon(_ symbol: String, label: String, glass: Bool = false) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(), target: nil, action: nil)
    button.bezelStyle = glass ? .glass : .accessoryBarAction
    button.isBordered = glass
    button.borderShape = .circle
    button.contentTintColor = .secondaryLabelColor
    button.symbolConfiguration = .init(pointSize: 15, weight: .regular)
    button.toolTip = label
    button.setAccessibilityLabel(label)
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: 32),
      button.heightAnchor.constraint(equalToConstant: 32),
    ])
    return button
  }

  private static func popup(_ titles: [String], symbol: String? = nil) -> NSPopUpButton {
    let popup = NSPopUpButton()
    popup.addItems(withTitles: titles)
    popup.font = .preferredFont(forTextStyle: .body)
    popup.isBordered = false
    popup.bezelStyle = .accessoryBarAction
    if let symbol { popup.item(at: 0)?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    popup.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
    return popup
  }

  private static func glass(_ content: NSView, radius: CGFloat = 22) -> NSGlassEffectView {
    let glass = NSGlassEffectView()
    glass.cornerRadius = radius
    glass.contentView = content
    if #available(macOS 27, *) { glass.effectIsInteractive = true }
    return glass
  }

  private static func footerView(_ variant: String) -> NSView {
    let account = popup(["Innei", "Innei Lab", "Settings…", "About Lody"], symbol: "person.crop.circle.fill")
    let help = icon("questionmark.circle", label: "About Lody")
    let archive = icon("archivebox", label: "Archived Sessions", glass: variant == "c")
    let settings = icon("gearshape", label: "Settings", glass: variant == "c")
    let content: NSView
    switch variant {
    case "b":
      content = stack([glass(stack([account], inset: 4)), spacer(), glass(stack([help, archive, settings], gap: 0, inset: 4))], gap: 8)
    case "c":
      content = stack([glass(stack([account], inset: 4)), spacer(), archive, settings], gap: 8)
    default:
      content = glass(stack([account, spacer(), help, archive, settings], gap: 0, inset: 4))
    }
    let root = stack([content], vertical: true)
    root.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 12, right: 12)
    content.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -24).isActive = true
    return root
  }

  private static func composerView(_ variant: String, newSession: Bool) -> NSView {
    let context: NSView
    if newSession {
      context = stack([
        popup(["lody-ios", "handbook"], symbol: "folder"),
        popup(["Mac Studio", "Mac mini"]),
        popup(["Claude Code", "Codex"]),
      ], gap: 8)
    } else {
      let label = NSTextField(labelWithString: "lody-ios  ·  mac-client  ·  Mac Studio")
      label.font = .systemFont(ofSize: 12)
      label.textColor = .secondaryLabelColor
      context = label
    }
    let input = MacComposerTextView()
    input.font = .preferredFont(forTextStyle: .body)
    input.string = "Keep the AppKit controls and align the sidebar rows."
    input.setAccessibilityIdentifier("chrome-study-input")
    input.isRichText = false
    input.drawsBackground = false
    input.isVerticallyResizable = true
    input.autoresizingMask = [.width]
    input.textContainerInset = .zero
    input.textContainer?.lineFragmentPadding = 0
    input.textContainer?.widthTracksTextView = true
    let scroll = NSScrollView()
    scroll.documentView = input
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.heightAnchor.constraint(equalToConstant: variant == "c" ? 44 : 64).isActive = true
    let attach = icon("paperclip", label: "Attach Files")
    let mode = popup(["Ask first", "Accept edits", "Full access"], symbol: "checkmark.shield")
    let model = popup(["Opus 5.5", "Sonnet 5.5"])
    let effort = popup(["High", "Medium", "Low"])
    let send = icon("arrow.up", label: newSession ? "New Session" : "Send", glass: true)
    send.bezelColor = .lodyAccent
    send.contentTintColor = .white
    let body: NSStackView
    let root: NSStackView
    switch variant {
    case "b":
      let editor = MacFillView(fill: .textBackgroundColor, radius: 16, border: true)
      let inner = stack([scroll], vertical: true, inset: 16)
      pin(inner, in: editor)
      scroll.widthAnchor.constraint(equalTo: inner.widthAnchor, constant: -32).isActive = true
      let tools = stack([
        glass(stack([attach, mode], gap: 4, inset: 4)), spacer(),
        glass(stack([model, effort, send], gap: 4, inset: 4)),
      ])
      root = stack([context, editor, tools], vertical: true, gap: 8)
      for view in [editor, tools] { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
    case "c":
      let entry = stack([attach, scroll, send], gap: 12)
      let editor = glass(stack([entry], vertical: true, inset: 12), radius: 24)
      let tools = stack([mode, spacer(), model, effort], gap: 8)
      root = stack([context, editor, tools], vertical: true, gap: 8)
      for view in [editor, tools] { view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
      entry.widthAnchor.constraint(equalTo: editor.widthAnchor, constant: -24).isActive = true
    default:
      let tools = stack([attach, mode, spacer(), model, effort, send], gap: 8)
      body = stack([context, scroll, tools], vertical: true, gap: 12, inset: 16)
      let sheet = glass(body, radius: 20)
      root = stack([sheet], vertical: true)
      sheet.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
      for view in [scroll, tools] { view.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -32).isActive = true }
    }
    root.setAccessibilityIdentifier("chrome-study-composer")
    return root
  }

  private static func pin(_ view: NSView, in parent: NSView) {
    view.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(view)
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
      view.topAnchor.constraint(equalTo: parent.topAnchor),
      view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
    ])
  }
}
#endif
