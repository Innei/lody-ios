import AppKit
import LodyData

@MainActor
final class SidebarSessionCell: NSTableCellView {
  init(row: MacSidebarModel.Row) {
    super.init(frame: .zero)
    let title = NSTextField(labelWithString: row.title)
    title.lineBreakMode = .byTruncatingTail
    title.font = .systemFont(ofSize: 13, weight: row.unread ? .semibold : .regular)
    title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    textField = title
    let glyph = NSImageView()
    glyph.symbolConfiguration = .init(pointSize: 8, weight: .bold)
    if row.attention {
      glyph.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)
      glyph.symbolConfiguration = .init(pointSize: 10, weight: .regular)
      glyph.contentTintColor = .systemOrange
    } else if MacSessionStatus.busy(row.status) {
      glyph.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
      glyph.contentTintColor = .controlAccentColor
    } else if row.unread {
      glyph.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
      glyph.contentTintColor = .secondaryLabelColor
    }
    let stack = NSStackView(views: [title, glyph])
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
      stack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    setAccessibilityLabel(row.title)
    setAccessibilityIdentifier("session-" + row.id)
  }

  required init?(coder: NSCoder) { nil }
}

@MainActor
enum MacSessionStatus {
  static func busy(_ status: String) -> Bool { OutboxDispatcher.busy.contains(status) }
}
