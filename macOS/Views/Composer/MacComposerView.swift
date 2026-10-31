import AppKit
import ChatAppKit
import LodyCore
import LodyData

@MainActor
final class MacComposerView: NSView, MacFileDropTarget {
  let project = NSPopUpButton()
  let machine = NSPopUpButton()
  let agent = NSPopUpButton()
  let input = MacComposerTextView()
  let mode = NSPopUpButton()
  let modelPicker = NSPopUpButton()
  let effort = NSPopUpButton()
  let send = NSButton()
  let notice = NSTextField(labelWithString: "")
  let attach = NSButton()
  let strip = CKAttachmentStripView()
  var onSend: (() -> Void)?
  var onDropFiles: (([URL]) -> Void)?
  private let tray = NSStackView()
  private let noticeRow = NSStackView()
  private let contextSurface = NSVisualEffectView()
  private let surface = NSGlassEffectView()
  private let body = NSStackView()
  private let inputScroll: NSScrollView
  private let inputHeight: NSLayoutConstraint
  private var preferredHeight: NSLayoutConstraint!
  private var bodyWidth: NSLayoutConstraint!
  private var trayWidth: NSLayoutConstraint!
  private var noticeWidth: NSLayoutConstraint!
  private var readingObserver: NSObjectProtocol?

  var reading = MacReading.current() {
    didSet {
      input.font = .systemFont(ofSize: reading.textSize)
      needsLayout = true
    }
  }

  override init(frame frameRect: NSRect) {
    let scroll = NSScrollView()
    inputScroll = scroll
    inputHeight = scroll.heightAnchor.constraint(equalToConstant: 40)
    super.init(frame: frameRect)
    surface.style = .regular
    surface.cornerRadius = 20
    surface.setContentHuggingPriority(.init(1), for: .horizontal)
    if #available(macOS 27, *) { surface.effectIsInteractive = true }
    surface.setAccessibilityIdentifier("composer-surface")
    for popup in [project, machine, agent, mode, modelPicker, effort] {
      popup.isBordered = false
      popup.controlSize = .regular
      popup.font = .preferredFont(forTextStyle: .body)
      popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    for popup in [project, machine, agent, modelPicker] {
      (popup.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
    }
    effort.contentTintColor = .secondaryLabelColor
    agent.imagePosition = .imageOnly
    agent.symbolConfiguration = .init(pointSize: 14, weight: .regular)
    project.setAccessibilityIdentifier("composer-project")
    machine.setAccessibilityIdentifier("composer-machine")
    agent.setAccessibilityIdentifier("composer-agent")
    mode.setAccessibilityIdentifier("composer-mode")
    modelPicker.setAccessibilityIdentifier("composer-model")
    effort.setAccessibilityIdentifier("composer-effort")
    notice.font = .systemFont(ofSize: 11)
    notice.textColor = .secondaryLabelColor
    notice.setAccessibilityIdentifier("composer-notice")
    notice.lineBreakMode = .byWordWrapping
    notice.maximumNumberOfLines = 2
    notice.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    tray.setViews([project, machine], in: .leading)
    tray.setViews([agent], in: .trailing)
    tray.spacing = 8
    tray.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 16, right: 12)
    contextSurface.material = .headerView
    contextSurface.blendingMode = .withinWindow
    contextSurface.wantsLayer = true
    contextSurface.layer?.cornerRadius = 16
    contextSurface.layer?.masksToBounds = true
    contextSurface.setAccessibilityIdentifier("composer-context-bar")
    input.font = .systemFont(ofSize: reading.textSize)
    input.isRichText = false
    input.drawsBackground = false
    input.textContainerInset = NSSize(width: 0, height: 8)
    input.textContainer?.lineFragmentPadding = 0
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
    attach.bezelStyle = .accessoryBarAction
    attach.isBordered = false
    attach.image = NSImage(systemSymbolName: "plus", accessibilityDescription: String(localized: "mac.attachments.attach", bundle: .lodyMac))
    attach.symbolConfiguration = .init(pointSize: 16, weight: .regular)
    attach.contentTintColor = .labelColor
    attach.setAccessibilityLabel(String(localized: "mac.attachments.attach", bundle: .lodyMac))
    attach.setAccessibilityIdentifier("composer-attach")
    attach.toolTip = String(localized: "mac.attachments.attach", bundle: .lodyMac)
    strip.editable = true
    strip.setAccessibilityIdentifier("composer-attachments")
    strip.labels = .init(
      remove: String(localized: "mac.attachments.remove", bundle: .lodyMac),
      failed: String(localized: "mac.attachments.failed", bundle: .lodyMac),
      uploading: { String(localized: "mac.attachments.uploading \($0)", bundle: .lodyMac) }
    )
    registerForDraggedTypes([.fileURL])
    let modelChoices = NSStackView(views: [modelPicker, effort])
    modelChoices.spacing = 0
    let spring = NSView()
    spring.translatesAutoresizingMaskIntoConstraints = false
    spring.setContentHuggingPriority(.init(1), for: .horizontal)
    spring.widthAnchor.constraint(greaterThanOrEqualToConstant: 0).isActive = true
    spring.widthAnchor.constraint(equalToConstant: 0).withPriority(.init(1)).isActive = true
    let controls = NSStackView(views: [attach, mode, spring, modelChoices, send])
    controls.distribution = .fill
    controls.spacing = 8
    controls.alignment = .centerY
    body.setViews([strip, scroll, controls], in: .leading)
    body.orientation = .vertical
    body.alignment = .leading
    body.spacing = 8
    body.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    noticeRow.addArrangedSubview(notice)
    noticeRow.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    for flexible in [controls, body, noticeRow, tray] {
      flexible.setHuggingPriority(.init(1), for: .horizontal)
      flexible.setContentHuggingPriority(.init(1), for: .horizontal)
    }
    let content = NSView()
    surface.contentView = content
    // These two material layers follow this view's bounds. Their fitting widths
    // must never propagate back into the window's reading-column constraints.
    addSubview(contextSurface)
    addSubview(surface)
    addSubview(noticeRow)
    // Internal stacks measure their height at the assigned width, without
    // autoresizing-mask constraints pinning an initial zero-size frame.
    for view in [body, tray, noticeRow] { view.translatesAutoresizingMaskIntoConstraints = false }
    bodyWidth = body.widthAnchor.constraint(equalToConstant: 0)
    trayWidth = tray.widthAnchor.constraint(equalToConstant: 0)
    noticeWidth = noticeRow.widthAnchor.constraint(equalToConstant: 0)
    content.addSubview(body)
    contextSurface.addSubview(tray)
    preferredHeight = heightAnchor.constraint(equalToConstant: 104)
    preferredHeight.priority = .init(999)
    preferredHeight.isActive = true
    NSLayoutConstraint.activate([
      agent.widthAnchor.constraint(equalToConstant: 32),
      agent.heightAnchor.constraint(equalToConstant: 32),
      notice.widthAnchor.constraint(lessThanOrEqualTo: noticeRow.widthAnchor, constant: -16),
      strip.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -24),
      scroll.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -24),
      controls.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -24),
      controls.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
      inputHeight,
      attach.widthAnchor.constraint(equalToConstant: 32),
      attach.heightAnchor.constraint(equalToConstant: 32),
      send.widthAnchor.constraint(equalToConstant: 32),
      send.heightAnchor.constraint(equalToConstant: 32),
    ])
    setAccessibilityIdentifier("composer")
    readingObserver = NotificationCenter.default.addObserver(forName: .lodyMacReadingDidChange, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.reading = .current() }
    }
  }

  required init?(coder: NSCoder) { nil }

  isolated deinit {
    readingObserver.map(NotificationCenter.default.removeObserver)
  }

  func render(_ model: MacComposerModel, reply: (project: String, branch: String, machine: String)) {
    let newSession = model.mode == .newSession
    for popup in [project, machine, agent] { popup.isHidden = !newSession }
    contextSurface.isHidden = !newSession
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
      selectedSymbol(form.chat ? "bubble.left" : "folder", on: project)
      selectedSymbol("laptopcomputer", on: machine)
      selectedSymbol("gearshape", on: agent)
      agent.toolTip = agent.titleOfSelectedItem
      notice.stringValue = model.attachmentNotice.isEmpty ? Self.notice(model) : model.attachmentNotice
    } else {
      input.setAccessibilityHelp([reply.project, reply.branch, reply.machine].filter { !$0.isEmpty }.joined(separator: "  ·  "))
      notice.stringValue = model.attachmentNotice
    }
    notice.isHidden = notice.stringValue.isEmpty
    noticeRow.isHidden = notice.isHidden
    strip.render(model.attachments.items.map(\.attachment))
    strip.isHidden = model.attachments.isEmpty
    let choice = model.choice
    fill(mode, model.modes.map(\.name), selected: model.modes.firstIndex { $0.id == choice.modeId } ?? (model.modes.isEmpty ? nil : 0))
    mode.isHidden = model.modes.isEmpty
    let full = choice.modeId.map(MacComposerModel.isFullAccess) ?? false
    mode.contentTintColor = .secondaryLabelColor
    for item in mode.itemArray {
      let warning = MacComposerModel.isFullAccess(model.modes[mode.index(of: item)].id)
      item.image = NSImage(systemSymbolName: warning ? "exclamationmark.shield" : "checkmark.shield", accessibilityDescription: nil)
      item.image?.size = NSSize(width: 14, height: 14)
    }
    mode.contentTintColor = full ? .systemOrange : .secondaryLabelColor
    fill(modelPicker, model.models.map(\.name), selected: model.models.firstIndex { $0.id == choice.modelId } ?? (model.models.isEmpty ? nil : 0))
    modelPicker.isHidden = model.models.isEmpty
    fill(effort, model.efforts.map(\.capitalized), selected: model.efforts.firstIndex { $0 == choice.effort })
    effort.isHidden = model.efforts.isEmpty
    (modelPicker.cell as? NSPopUpButtonCell)?.arrowPosition = model.efforts.isEmpty ? .arrowAtCenter : .noArrow
    send.isEnabled = model.canSend
    send.alphaValue = model.canSend ? 1 : 0.4
    needsLayout = true
  }

  override func layout() {
    super.layout()
    guard bounds.width > 24 else { return }
    bodyWidth.constant = bounds.width
    trayWidth.constant = bounds.width - 24
    noticeWidth.constant = bounds.width - 24
    NSLayoutConstraint.activate([bodyWidth, trayWidth, noticeWidth])
    surface.frame.size = NSSize(width: bounds.width, height: max(surface.frame.height, 104))
    body.frame = surface.bounds
    surface.layoutSubtreeIfNeeded()
    updateInputHeight()
    body.layoutSubtreeIfNeeded()
    let surfaceHeight = ceil(body.fittingSize.height)
    var bottom: CGFloat = 0
    if !noticeRow.isHidden {
      noticeRow.frame.size.width = bounds.width - 24
      noticeRow.layoutSubtreeIfNeeded()
      let height = ceil(noticeRow.fittingSize.height)
      noticeRow.frame = NSRect(x: 12, y: 0, width: bounds.width - 24, height: height)
      bottom = height + 8
    }
    surface.frame = NSRect(x: 0, y: bottom, width: bounds.width, height: surfaceHeight)
    body.frame = surface.bounds
    var height = bottom + surfaceHeight
    if !contextSurface.isHidden {
      let trayHeight = ceil(tray.fittingSize.height)
      contextSurface.frame = NSRect(x: 12, y: height - 12, width: bounds.width - 24, height: trayHeight)
      tray.frame = contextSurface.bounds
      height += trayHeight - 12
    }
    if abs(preferredHeight.constant - height) > 0.5 { preferredHeight.constant = height }
  }

  private func updateInputHeight() {
    guard inputScroll.contentSize.width > 0, let container = input.textContainer, let manager = input.layoutManager, let font = input.font else { return }
    input.frame.size.width = inputScroll.contentSize.width
    manager.ensureLayout(for: container)
    let inset = input.textContainerInset.height * 2
    let required = ceil(manager.usedRect(for: container).height + inset)
    let maximum = ceil(manager.defaultLineHeight(for: font) * 8 + inset)
    let next = max(40, min(required, maximum))
    if abs(inputHeight.constant - next) > 0.5 { inputHeight.constant = next }
  }

  private func selectedSymbol(_ symbol: String, on popup: NSPopUpButton) {
    let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    image?.size = NSSize(width: 14, height: 14)
    popup.selectedItem?.image = image
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

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    Self.fileURLs(sender.draggingPasteboard).isEmpty ? [] : .copy
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = Self.fileURLs(sender.draggingPasteboard)
    guard !urls.isEmpty else { return false }
    dropFiles(urls)
    return true
  }

  func dropFiles(_ urls: [URL]) { onDropFiles?(urls) }

  static func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
    pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
  }
}

@MainActor
final class MacComposerTextView: NSTextView {
  var onSubmit: (() -> Void)?
  var onPasteAttachments: ((NSPasteboard) -> Bool)?
  var onDropFiles: (([URL]) -> Void)?

  override func paste(_ sender: Any?) {
    if onPasteAttachments?(.general) == true { return }
    super.paste(sender)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = MacComposerView.fileURLs(sender.draggingPasteboard)
    guard !urls.isEmpty, let onDropFiles else { return super.performDragOperation(sender) }
    onDropFiles(urls)
    return true
  }
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
    let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height)
    (placeholder as NSString).draw(at: origin, withAttributes: [
      .font: font ?? .systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor,
    ])
  }

  override func accessibilityPlaceholderValue() -> String? { placeholder }
}
