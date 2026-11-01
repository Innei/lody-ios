import AppKit

@MainActor
final class MacQueueController: NSViewController, NSTextViewDelegate {
  let model: MacQueueModel
  private let stack = NSStackView()
  private var editor: NSTextView?
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
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 14
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
    root.setAccessibilityIdentifier("session-queue")
    view = root
    render()
    Task { await model.reload() }
  }

  private func render() {
    guard isViewLoaded else { return }
    stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
    let heading = NSTextField(labelWithString: Self.text("mac.queue.title"))
    heading.font = .preferredFont(forTextStyle: .title2)
    let top = NSStackView(views: [heading, NSView(), button("mac.queue.refresh", "queue-refresh") { [weak self] in Task { await self?.model.reload() } },
      button("mac.queue.close", "queue-close") { [weak self] in self?.close() }])
    add(top)
    if !model.error.isEmpty {
      let error = NSTextField(wrappingLabelWithString: model.error)
      error.textColor = .systemOrange
      error.setAccessibilityIdentifier("queue-error")
      add(error)
    }
    if model.blocked { add(button("mac.queue.reconnect", "queue-reconnect") { [weak self] in self?.reconnect?() }) }
    if model.items.isEmpty { add(NSTextField(labelWithString: Self.text(model.busy ? "mac.queue.loading" : "mac.queue.empty"))) }
    for (index, item) in model.items.enumerated() {
      let text = NSTextField(wrappingLabelWithString: item.text)
      text.isSelectable = true
      text.setAccessibilityIdentifier("queue-message-\(index)")
      add(text)
      if !item.attachments.isEmpty {
        let files = NSTextField(wrappingLabelWithString: item.attachments.joined(separator: ", "))
        files.textColor = .secondaryLabelColor
        add(files)
      }
      if model.editing?.id == item.id {
        let scroll = NSTextView.scrollableTextView()
        let input = scroll.documentView as! NSTextView
        input.isRichText = false
        input.string = model.text
        input.font = .preferredFont(forTextStyle: .body)
        input.delegate = self
        input.setAccessibilityIdentifier("queue-editor")
        editor = input
        add(scroll)
        scroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
        add(NSStackView(views: [button("mac.queue.save", "queue-save") { [weak self] in Task { await self?.model.save() } },
          button("mac.queue.cancel", "queue-cancel") { [weak self] in Task { await self?.model.cancel() } }]))
      } else {
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
        up.isEnabled = up.isEnabled && index > 0
        down.isEnabled = down.isEnabled && index < model.items.count - 1
        steer.isEnabled = steer.isEnabled && item.messageId != nil && model.canSteer(index)
        add(NSStackView(views: [edit, remove, up, down, steer]))
      }
      let separator = NSBox()
      separator.boxType = .separator
      add(separator)
    }
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
  private func add(_ child: NSView) {
    stack.addArrangedSubview(child)
    child.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
  }
  private func button(_ key: String, _ id: String, action: @escaping () -> Void) -> NSButton {
    let button = MacQueueButton(title: Self.text(key), action: action)
    button.setAccessibilityIdentifier(id)
    button.isEnabled = !model.busy
    return button
  }
  private static func text(_ key: String) -> String { String(localized: String.LocalizationValue(key), bundle: .lodyMac) }
}

@MainActor
final class MacQueueButton: NSButton {
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
