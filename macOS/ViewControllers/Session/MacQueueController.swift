import AppKit

@MainActor
final class MacQueueController: NSViewController, NSTextViewDelegate {
  let model: MacQueueModel
  private let stack = NSStackView()
  private let rows = NSStackView()
  private let editingSection = NSStackView()
  private let conflictSection = NSStackView()
  private let error = NSTextField(wrappingLabelWithString: "")
  private var editor: NSTextView?
  private var editingId: String?
  private var renderedConflict: String?
  private var refresh: NSButton?
  private var closeButton: NSButton?
  private var reconnectButton: NSButton?
  private var editorButtons: [NSButton] = []
  var reconnect: (() -> Void)?

  init(model: MacQueueModel) {
    self.model = model
    super.init(nibName: nil, bundle: nil)
    model.changed = { [weak self] in self?.render() }
  }
  required init?(coder: NSCoder) { nil }

  override func loadView() {
    preferredContentSize = NSSize(width: 640, height: 460)
    let root = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    for section in [stack, rows, editingSection, conflictSection] {
      section.orientation = .vertical
      section.alignment = .leading
      section.spacing = 14
    }
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.documentView = stack
    scroll.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(scroll)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: root.topAnchor), scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
    ])
    let heading = NSTextField(labelWithString: Self.text("mac.queue.title"))
    heading.font = .preferredFont(forTextStyle: .title2)
    let refresh = button("mac.queue.refresh", "queue-refresh") { [weak self] in Task { await self?.model.reload() } }
    let close = button("mac.queue.close", "queue-close") { [weak self] in self?.close() }
    self.refresh = refresh
    closeButton = close
    add(NSStackView(views: [heading, NSView(), refresh, close]), to: stack, inset: 40)
    error.textColor = .systemOrange
    error.setAccessibilityIdentifier("queue-error")
    add(error, to: stack, inset: 40)
    let reconnect = button("mac.queue.reconnect", "queue-reconnect") { [weak self] in self?.reconnect?() }
    reconnectButton = reconnect
    add(reconnect, to: stack, inset: 40)
    for section in [conflictSection, editingSection, rows] { add(section, to: stack, inset: 40) }
    root.setAccessibilityIdentifier("session-queue")
    view = root
    render()
    Task { await model.reload() }
  }

  private func render() {
    guard isViewLoaded else { return }
    refresh?.isEnabled = !model.busy
    closeButton?.isEnabled = !model.busy
    reconnectButton?.isHidden = !model.blocked
    error.stringValue = model.error
    error.isHidden = model.error.isEmpty
    renderEditor()
    renderConflict()
    clear(rows)
    if model.items.isEmpty, !model.blocked { add(NSTextField(labelWithString: Self.text(model.busy ? "mac.queue.loading" : "mac.queue.empty")), to: rows) }
    for (index, item) in model.items.enumerated() where model.editing?.id != item.id {
      let text = NSTextField(wrappingLabelWithString: item.text)
      text.isSelectable = true
      text.setAccessibilityIdentifier("queue-message-\(index)")
      add(text, to: rows)
      if !item.attachments.isEmpty { add(files(item.attachments), to: rows) }
      let edit = button("mac.queue.edit", "queue-edit-\(index)") { [weak self] in Task { await self?.model.begin(item) } }
      let remove = button("mac.queue.remove", "queue-remove-\(index)") { [weak self] in Task { await self?.model.remove(item) } }
      let up = button("mac.queue.up", "queue-up-\(index)") { [weak self] in
        guard let self, index > 0, model.items.indices.contains(index - 1) else { return }
        Task { await model.move(item, over: model.items[index - 1]) }
      }
      let down = button("mac.queue.down", "queue-down-\(index)") { [weak self] in
        guard let self, model.items.indices.contains(index + 1) else { return }
        Task { await model.move(item, over: model.items[index + 1]) }
      }
      let steer = button("mac.queue.steer", "queue-steer-\(index)") { [weak self] in self?.model.steer(item) }
      for button in [edit, remove, up, down, steer] { button.isEnabled = !model.busy && !model.blocked && !item.editing && model.editing == nil }
      edit.isEnabled = edit.isEnabled && model.conflictText == nil
      up.isEnabled = up.isEnabled && index > 0
      down.isEnabled = down.isEnabled && index < model.items.count - 1
      steer.isEnabled = steer.isEnabled && item.messageId != nil && model.canSteer(index)
      add(NSStackView(views: [edit, remove, up, down, steer]), to: rows)
      let separator = NSBox()
      separator.boxType = .separator
      add(separator, to: rows)
    }
  }

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
        scroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
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
    scroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
    add(NSStackView(views: [button("mac.queue.copyUnsaved", "queue-copy-unsaved") { [weak self] in
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
      self?.model.discardConflict()
    }, button("mac.queue.discardUnsaved", "queue-discard-unsaved") { [weak self] in self?.model.discardConflict() }]), to: conflictSection)
  }

  func textDidChange(_ notification: Notification) { model.text = editor?.string ?? "" }
  private func close() {
    Task { [weak self] in
      guard let self else { return }
      if model.editing != nil { await model.cancel() }
      guard !model.busy, model.editing == nil || model.blocked else { return }
      dismiss(nil)
    }
  }
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
