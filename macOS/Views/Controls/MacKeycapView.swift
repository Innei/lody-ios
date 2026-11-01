import AppKit

@MainActor
final class MacKeycapView: NSView {
  enum Key: String { case returnKey = "↩", escape = "⎋" }
  private let border = NSBox()
  private let glyph: NSTextField
  var isEnabled = true { didSet { render() } }
  var contentColor: NSColor { isEnabled ? .labelColor : .disabledControlTextColor }

  init(key: Key) {
    glyph = NSTextField(labelWithString: key.rawValue)
    super.init(frame: .zero)
    border.boxType = .custom
    border.titlePosition = .noTitle
    border.borderType = .lineBorder
    border.borderWidth = 1
    border.cornerRadius = 4
    border.fillColor = .clear
    border.contentViewMargins = .zero
    let content = NSView()
    border.contentView = content
    border.translatesAutoresizingMaskIntoConstraints = false
    addSubview(border)
    glyph.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    glyph.alignment = .center
    glyph.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(glyph)
    NSLayoutConstraint.activate([
      border.leadingAnchor.constraint(equalTo: leadingAnchor), border.trailingAnchor.constraint(equalTo: trailingAnchor),
      border.topAnchor.constraint(equalTo: topAnchor), border.bottomAnchor.constraint(equalTo: bottomAnchor),
      glyph.centerXAnchor.constraint(equalTo: content.centerXAnchor), glyph.centerYAnchor.constraint(equalTo: content.centerYAnchor),
    ])
    setContentHuggingPriority(.required, for: .horizontal)
    setContentCompressionResistancePriority(.required, for: .horizontal)
    for view in [self, border, glyph] { view.setAccessibilityElement(false) }
    render()
  }
  required init?(coder: NSCoder) { nil }
  override var intrinsicContentSize: NSSize { NSSize(width: 18, height: 18) }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); render() }

  private func render() {
    glyph.textColor = contentColor
    effectiveAppearance.performAsCurrentDrawingAppearance {
      border.borderColor = contentColor.withAlphaComponent(contentColor.alphaComponent * 0.35)
    }
  }
}

@MainActor
final class MacKeycapButton: NSButton {
  private let caption = NSTextField(labelWithString: "")
  private let keycap: MacKeycapView
  private let content = MacKeycapButtonContent()
  private var ready = false
  override var isEnabled: Bool { didSet { render() } }
  override var title: String { didSet { render() } }
  override var font: NSFont? { didSet { render() } }

  init(title: String, key: MacKeycapView.Key) {
    keycap = MacKeycapView(key: key)
    super.init(frame: .zero)
    cell = MacKeycapButtonCell(textCell: "")
    setButtonType(.momentaryPushIn)
    isBordered = false
    self.title = title
    caption.setAccessibilityElement(false)
    content.addArrangedSubview(caption)
    content.addArrangedSubview(keycap)
    content.spacing = 8
    content.alignment = .centerY
    content.translatesAutoresizingMaskIntoConstraints = false
    content.setAccessibilityElement(false)
    addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
      content.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    ready = true
    render()
  }
  required init?(coder: NSCoder) { nil }
  override var intrinsicContentSize: NSSize {
    NSSize(width: caption.intrinsicContentSize.width + content.spacing + keycap.intrinsicContentSize.width,
           height: max(caption.intrinsicContentSize.height, keycap.intrinsicContentSize.height))
  }
  override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); render() }

  private func render() {
    guard ready else { return }
    caption.stringValue = title
    caption.font = font ?? .preferredFont(forTextStyle: .body)
    keycap.isEnabled = isEnabled
    caption.textColor = keycap.contentColor
    invalidateIntrinsicContentSize()
  }
}

@MainActor
private final class MacKeycapButtonCell: NSButtonCell {
  override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect { frame }
}

@MainActor
private final class MacKeycapButtonContent: NSStackView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
