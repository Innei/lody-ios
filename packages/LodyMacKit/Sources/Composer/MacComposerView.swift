import AppKit
import LodyCore
import LodyData

@MainActor
final class MacComposerView: NSView {
  let project = NSPopUpButton()
  let machine = NSPopUpButton()
  let agent = NSPopUpButton()
  let context = NSTextField(labelWithString: "")
  let input = MacComposerTextView()
  let mode = NSPopUpButton()
  let modelPicker = NSPopUpButton()
  let effort = NSPopUpButton()
  let send = NSButton()
  let notice = NSTextField(labelWithString: "")
  var onSend: (() -> Void)?
  private let tray = NSStackView()
  private let inputHeight: NSLayoutConstraint

  override init(frame frameRect: NSRect) {
    let scroll = NSScrollView()
    inputHeight = scroll.heightAnchor.constraint(equalToConstant: 44)
    super.init(frame: frameRect)
    let fill = MacFillView(fill: .controlBackgroundColor, radius: 16, border: true)
    for popup in [project, machine, agent, mode, modelPicker, effort] {
      popup.isBordered = false
      popup.controlSize = .small
      popup.font = .systemFont(ofSize: 12)
    }
    project.setAccessibilityIdentifier("composer-project")
    machine.setAccessibilityIdentifier("composer-machine")
    agent.setAccessibilityIdentifier("composer-agent")
    mode.setAccessibilityIdentifier("composer-mode")
    context.font = .systemFont(ofSize: 12)
    context.textColor = .secondaryLabelColor
    context.setAccessibilityIdentifier("composer-context")
    notice.font = .systemFont(ofSize: 11)
    notice.textColor = .secondaryLabelColor
    notice.setAccessibilityIdentifier("composer-notice")
    notice.lineBreakMode = .byWordWrapping
    notice.maximumNumberOfLines = 2
    notice.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    tray.setViews([project, machine, agent, context], in: .leading)
    tray.spacing = 4
    input.font = .systemFont(ofSize: 13)
    input.isRichText = false
    input.drawsBackground = false
    input.textContainerInset = NSSize(width: 2, height: 6)
    input.allowsUndo = true
    input.isVerticallyResizable = true
    input.autoresizingMask = [.width]
    input.textContainer?.widthTracksTextView = true
    input.onSubmit = { [weak self] in self?.onSend?() }
    input.setAccessibilityIdentifier("composer-input")
    scroll.documentView = input
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    send.bezelStyle = .circular
    send.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: String(localized: "mac.composer.send", bundle: .lodyMac))
    send.title = ""
    send.bezelColor = .lodyAccent
    send.contentTintColor = .white
    send.target = self
    send.action = #selector(sendPressed)
    send.setAccessibilityIdentifier("composer-send")
    send.setAccessibilityLabel(String(localized: "mac.composer.send", bundle: .lodyMac))
    let controls = NSStackView()
    controls.setViews([mode], in: .leading)
    controls.setViews([modelPicker, effort, send], in: .trailing)
    let stack = NSStackView(views: [tray, notice, scroll, controls])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 10)
    for view in [fill, stack] { view.translatesAutoresizingMaskIntoConstraints = false }
    addSubview(fill)
    fill.addSubview(stack)
    NSLayoutConstraint.activate([
      fill.topAnchor.constraint(equalTo: topAnchor),
      fill.leadingAnchor.constraint(equalTo: leadingAnchor),
      fill.trailingAnchor.constraint(equalTo: trailingAnchor),
      fill.bottomAnchor.constraint(equalTo: bottomAnchor),
      stack.topAnchor.constraint(equalTo: fill.topAnchor),
      stack.leadingAnchor.constraint(equalTo: fill.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: fill.trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: fill.bottomAnchor),
      tray.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -22),
      notice.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor, constant: -26),
      scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -22),
      controls.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -22),
      inputHeight,
      send.widthAnchor.constraint(equalToConstant: 28),
      send.heightAnchor.constraint(equalToConstant: 28),
    ])
    setAccessibilityIdentifier("composer")
  }

  required init?(coder: NSCoder) { nil }

  func render(_ model: MacComposerModel, reply: (project: String, branch: String, machine: String)) {
    let newSession = model.mode == .newSession
    for popup in [project, machine, agent] { popup.isHidden = !newSession }
    context.isHidden = newSession
    input.placeholder = String(localized: newSession ? "mac.composer.placeholder.new" : "mac.composer.placeholder.reply", bundle: .lodyMac)
    if newSession {
      let form = model.form
      fill(project, form.projects.map(\.name) + [String(localized: "mac.composer.chat", bundle: .lodyMac)],
           selected: form.chat ? form.projects.count : form.projects.firstIndex { $0.id == form.current.projectId })
      let machines = form.current.machines
      fill(machine, machines.map(\.name), selected: machines.firstIndex { $0.id == form.current.machine?.id },
           empty: String(localized: "mac.composer.noMachine", bundle: .lodyMac))
      let agents = form.current.agents
      fill(agent, agents.map(\.name), selected: agents.firstIndex { $0.key == form.current.agentKey },
           empty: String(localized: "mac.composer.noAgent", bundle: .lodyMac))
      notice.stringValue = Self.notice(model)
      notice.isHidden = notice.stringValue.isEmpty
    } else {
      context.stringValue = [reply.project, reply.branch, reply.machine].filter { !$0.isEmpty }.joined(separator: "  ·  ")
      notice.isHidden = true
    }
    let choice = model.choice
    fill(mode, model.modes.map(\.name), selected: model.modes.firstIndex { $0.id == choice.modeId } ?? (model.modes.isEmpty ? nil : 0))
    mode.isHidden = model.modes.isEmpty
    let full = choice.modeId.map(MacComposerModel.isFullAccess) ?? false
    mode.contentTintColor = full ? .systemOrange : nil
    fill(modelPicker, model.models.map(\.name), selected: model.models.firstIndex { $0.id == choice.modelId } ?? (model.models.isEmpty ? nil : 0))
    modelPicker.isHidden = model.models.isEmpty
    fill(effort, model.efforts.map(\.capitalized), selected: model.efforts.firstIndex { $0 == choice.effort })
    effort.isHidden = model.efforts.isEmpty
    send.isEnabled = model.canSend
    send.alphaValue = model.canSend ? 1 : 0.4
    let lines = max(1, min(8, input.string.split(separator: "\n", omittingEmptySubsequences: false).count))
    inputHeight.constant = CGFloat(lines) * 17 + 14
  }

  private static func notice(_ model: MacComposerModel) -> String {
    switch model.missing {
    case .project: String(localized: "mac.composer.needProject", bundle: .lodyMac)
    case .machine: String(localized: "mac.composer.needMachine", bundle: .lodyMac)
    case .agent: String(localized: "mac.composer.needAgent", bundle: .lodyMac)
    case nil: model.form.current.loading ? String(localized: "mac.composer.loading", bundle: .lodyMac) : ""
    }
  }

  private func fill(_ popup: NSPopUpButton, _ titles: [String], selected: Int?, empty: String = "") {
    let current = popup.itemTitles
    let wanted = titles.isEmpty && !empty.isEmpty ? [empty] : titles
    if current != wanted {
      popup.removeAllItems()
      popup.addItems(withTitles: wanted)
    }
    popup.isEnabled = !titles.isEmpty
    if let selected, wanted.indices.contains(selected) { popup.selectItem(at: selected) }
  }

  @objc private func sendPressed() { onSend?() }
}

@MainActor
final class MacComposerTextView: NSTextView {
  var onSubmit: (() -> Void)?
  var placeholder = "" { didSet { needsDisplay = true } }

  override func keyDown(with event: NSEvent) {
    let plain = event.modifierFlags.intersection([.shift, .option, .command, .control]).isEmpty
    if plain, event.keyCode == 36 || event.keyCode == 76, !hasMarkedText() {
      onSubmit?()
      return
    }
    super.keyDown(with: event)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard string.isEmpty, !placeholder.isEmpty else { return }
    let origin = NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height)
    (placeholder as NSString).draw(at: origin, withAttributes: [
      .font: font ?? .systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor,
    ])
  }

  override func accessibilityPlaceholderValue() -> String? { placeholder }
}
