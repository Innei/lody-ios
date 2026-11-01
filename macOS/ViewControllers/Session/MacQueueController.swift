import AppKit

@MainActor
final class MacQueueController: NSViewController, NSTextViewDelegate {
  let model: MacQueueModel
  private let stack = MacQueueStack()
  private let rows = NSStackView()
  private let editingSection = NSStackView()
  private let conflictSection = NSStackView()
  private let error = NSTextField(wrappingLabelWithString: "")
  private var editor: NSTextView?
  private var editingId: String?
  private var renderedConflict: String?
  private var reconnectButton: NSButton?
  private var editorButtons: [NSButton] = []
  var onHeightChange: (() -> Void)?
  var reconnect: (() -> Void)?

  init(model: MacQueueModel) {
    self.model = model
    super.init(nibName: nil, bundle: nil)
    model.changed = { [weak self] in self?.render() }
  }
  required init?(coder: NSCoder) { nil }

  override func loadView() {
    preferredContentSize = NSSize(width: 640, height: 0)
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 44))
    let surface = MacComposerTrayView()
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    for section in [stack, rows, editingSection, conflictSection] {
      section.orientation = .vertical
      section.alignment = .leading
      section.spacing = 8
    }
    rows.spacing = 0
    stack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4 + MacComposerTrayView.overlap, right: 12)
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = stack
    surface.translatesAutoresizingMaskIntoConstraints = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    surface.addSubview(scroll)
    root.addSubview(surface)
    NSLayoutConstraint.activate([
      surface.leadingAnchor.constraint(equalTo: root.leadingAnchor), surface.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      surface.topAnchor.constraint(equalTo: root.topAnchor), surface.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: surface.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: surface.topAnchor), scroll.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
      stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
    ])
    error.textColor = .systemOrange
    error.setAccessibilityIdentifier("queue-error")
    add(error, to: stack, inset: 28)
    let reconnect = button("mac.queue.reconnect", "queue-reconnect") { [weak self] in self?.reconnect?() }
    reconnectButton = reconnect
    add(reconnect, to: stack, inset: 28)
    for section in [conflictSection, editingSection, rows] { add(section, to: stack, inset: 28) }
    root.setAccessibilityIdentifier("session-queue")
    view = root
    render()
    Task { await model.reload() }
  }

  private func render() {
    guard isViewLoaded else { return }
    reconnectButton?.isHidden = !model.blocked
    error.stringValue = model.error
    error.isHidden = model.error.isEmpty
    renderEditor()
    renderConflict()
    clear(rows)
    for (index, item) in model.items.enumerated() where model.editing?.id != item.id {
      let enabled = !model.busy && !model.blocked && !item.editing && model.editing == nil
      let text = MacActionButton(title: item.text.isEmpty ? String(localized: "native.chat.row.queuedAttachmentsOnly", bundle: .lodyData) : item.text) { [weak self] in Task { await self?.model.begin(item) } }
      text.isBordered = false
      text.alignment = .left
      text.font = .systemFont(ofSize: 15)
      text.contentTintColor = .secondaryLabelColor
      text.setAccessibilityIdentifier("queue-message-\(index)")
      text.setAccessibilityLabel(text.title)
      text.isEnabled = enabled && model.conflictText == nil
      let content = NSStackView(views: [text])
      content.orientation = .vertical
      content.alignment = .leading
      content.spacing = 2
      content.setHuggingPriority(.init(1), for: .horizontal)
      content.setContentHuggingPriority(.init(1), for: .horizontal)
      text.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
      if !item.attachments.isEmpty {
        let caption = files(item.attachments)
        caption.font = .systemFont(ofSize: 12)
        content.addArrangedSubview(caption)
      }
      let steer = button("mac.queue.steer", "queue-steer-\(index)") { [weak self] in self?.model.steer(item) }
      steer.title = ""
      steer.image = NSImage(systemSymbolName: "arrow.up.circle", accessibilityDescription: nil)
      steer.isBordered = false
      steer.contentTintColor = .lodyAccent
      steer.setAccessibilityLabel(Self.text("mac.queue.steer") + ": " + item.text)
      steer.isEnabled = enabled && item.messageId != nil && model.canSteer(index)
      let row = NSStackView(views: [content, steer])
      row.alignment = .centerY
      row.distribution = .fill
      row.spacing = 8
      row.heightAnchor.constraint(equalToConstant: item.attachments.isEmpty ? 40 : 52).isActive = true
      steer.widthAnchor.constraint(equalToConstant: 36).isActive = true
      steer.heightAnchor.constraint(equalToConstant: 36).isActive = true
      let menu = NSMenu()
      menu.autoenablesItems = false
      func action(_ key: String, enabled: Bool, perform: @escaping () -> Void) {
        let entry = MacQueueMenuItem(title: Self.text(key), action: perform)
        entry.isEnabled = enabled
        menu.addItem(entry)
      }
      action("mac.queue.edit", enabled: enabled && model.conflictText == nil) { [weak self] in Task { await self?.model.begin(item) } }
      action("mac.queue.remove", enabled: enabled) { [weak self] in Task { await self?.model.remove(item) } }
      menu.addItem(.separator())
      action("mac.queue.up", enabled: enabled && index > 0) { [weak self] in
        guard let self, let i = model.items.firstIndex(where: { $0.id == item.id }), i > 0 else { return }
        Task { await model.move(item, over: model.items[i - 1]) }
      }
      action("mac.queue.down", enabled: enabled && index < model.items.count - 1) { [weak self] in
        guard let self, let i = model.items.firstIndex(where: { $0.id == item.id }), i + 1 < model.items.count else { return }
        Task { await model.move(item, over: model.items[i + 1]) }
      }
      row.menu = menu
      text.menu = menu
      add(row, to: rows)
      if index < model.items.count - 1 { let line = NSBox(); line.boxType = .separator; add(line, to: rows) }
    }
    let visible = !model.items.isEmpty || model.blocked || !model.error.isEmpty || model.conflictText != nil
    var height: CGFloat = model.items.prefix(3).reduce(8) { $0 + ($1.attachments.isEmpty ? 40 : 52) }
    if model.editing != nil || model.conflictText != nil { height = max(172, min(300, height + 100)) }
    if !model.error.isEmpty { height += 44 }
    if model.blocked { height += 32 }
    preferredContentSize.height = visible ? height + MacComposerTrayView.overlap : 0
    onHeightChange?()
  }

  func refreshControls() { render() }

  private func renderEditor() {
    let next = model.editing.map { $0.id + "\n" + ($0.editToken ?? "") }
    if editingId != next {
      editingId = next
      clear(editingSection)
      editor = nil
      editorButtons = []
      if let item = model.editing {
        add(NSTextField(wrappingLabelWithString: item.text), to: editingSection)
        if !item.attachments.isEmpty { add(files(item.attachments), to: editingSection) }
        let scroll = NSTextView.scrollableTextView()
        let input = scroll.documentView as! NSTextView
        input.isRichText = false
        input.string = model.text
        input.font = .preferredFont(forTextStyle: .body)
        input.delegate = self
        input.setAccessibilityIdentifier("queue-editor")
        editor = input
        add(scroll, to: editingSection)
        scroll.heightAnchor.constraint(equalToConstant: 64).isActive = true
        editorButtons = [button("mac.queue.save", "queue-save") { [weak self] in Task { await self?.model.save() } },
                         button("mac.queue.cancel", "queue-cancel") { [weak self] in Task { await self?.model.cancel() } }]
        add(NSStackView(views: editorButtons), to: editingSection)
      }
    }
    editingSection.isHidden = model.editing == nil
    // Reloads never remove, replace or reset the active editor/marked text.
    editorButtons.forEach { $0.isEnabled = !model.busy && !model.blocked }
    let editable = !model.committing && !model.blocked
    if editor?.isEditable != editable { editor?.isEditable = editable }
  }

  private func renderConflict() {
    conflictSection.isHidden = model.conflictText == nil
    guard renderedConflict != model.conflictText else { return }
    renderedConflict = model.conflictText
    clear(conflictSection)
    conflictSection.isHidden = model.conflictText == nil
    guard let text = model.conflictText else { return }
    let scroll = NSTextView.scrollableTextView()
    let input = scroll.documentView as! NSTextView
    input.string = text
    input.isEditable = false
    input.isSelectable = true
    input.font = .preferredFont(forTextStyle: .body)
    input.setAccessibilityIdentifier("queue-unsaved")
    add(scroll, to: conflictSection)
    scroll.heightAnchor.constraint(equalToConstant: 64).isActive = true
    add(NSStackView(views: [button("mac.queue.copyUnsaved", "queue-copy-unsaved") { [weak self] in
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      self?.model.discardConflict()
    }, button("mac.queue.discardUnsaved", "queue-discard-unsaved") { [weak self] in self?.model.discardConflict() }]), to: conflictSection)
  }

  func textDidChange(_ notification: Notification) { model.text = editor?.string ?? "" }
  private func files(_ names: [String]) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: names.joined(separator: ", "))
    label.textColor = .secondaryLabelColor
    return label
  }
  private func clear(_ section: NSStackView) { section.arrangedSubviews.forEach { section.removeArrangedSubview($0); $0.removeFromSuperview() } }
  private func add(_ child: NSView, to section: NSStackView, inset: CGFloat = 0) {
    section.addArrangedSubview(child)
    child.widthAnchor.constraint(equalTo: section.widthAnchor, constant: -inset).isActive = true
  }
  private func button(_ key: String, _ id: String, action: @escaping () -> Void) -> NSButton {
    let button = MacActionButton(title: Self.text(key), action: action)
    button.setAccessibilityIdentifier(id)
    return button
  }
  private static func text(_ key: String) -> String { String(localized: String.LocalizationValue(key), bundle: .lodyMac) }
}

private final class MacQueueStack: NSStackView { override var isFlipped: Bool { true } }

@MainActor
private final class MacQueueMenuItem: NSMenuItem {
  private let perform: () -> Void
  init(title: String, action: @escaping () -> Void) {
    perform = action
    super.init(title: title, action: #selector(selected), keyEquivalent: "")
    target = self
  }
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  @objc private func selected() { perform() }
}
