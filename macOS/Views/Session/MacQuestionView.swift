import AppKit
import LodyData

/// The option row from the approved interruption study, shared by approval and questions.
@MainActor
final class MacInterruptionOption: NSView {
  let button: NSButton
  private let fill = NSBox()

  init(title: String, detail: String = "", index: Int, multiple: Bool = false, action: @escaping () -> Void) {
    button = MacActionButton(title: title, action: action)
    super.init(frame: .zero)
    button.setButtonType(multiple ? .switch : .radio)
    button.isBordered = false
    button.imagePosition = .imageOnly
    let heading = NSTextField(wrappingLabelWithString: title)
    heading.font = .preferredFont(forTextStyle: .body)
    heading.setAccessibilityElement(false)
    let labels = NSStackView(views: [heading])
    labels.orientation = .vertical
    labels.alignment = .leading
    labels.spacing = 2
    heading.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
    if !detail.isEmpty {
      let description = NSTextField(wrappingLabelWithString: detail)
      description.font = .preferredFont(forTextStyle: .subheadline)
      description.textColor = .secondaryLabelColor
      description.setAccessibilityElement(false)
      labels.addArrangedSubview(description)
      description.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
    }
    button.setAccessibilityLabel(title)
    button.setAccessibilityHelp(detail)
    let key = NSTextField(labelWithString: String(index + 1))
    key.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
    key.textColor = .secondaryLabelColor
    key.setAccessibilityElement(false)
    fill.boxType = .custom
    fill.borderType = .noBorder
    fill.titlePosition = .noTitle
    fill.cornerRadius = 8
    fill.contentViewMargins = .zero
    fill.fillColor = .clear
    for child in [fill, button, labels, key] { child.translatesAutoresizingMaskIntoConstraints = false }
    addSubview(fill)
    fill.contentView?.addSubview(button)
    fill.contentView?.addSubview(labels)
    fill.contentView?.addSubview(key)
    NSLayoutConstraint.activate([
      fill.leadingAnchor.constraint(equalTo: leadingAnchor), fill.trailingAnchor.constraint(equalTo: trailingAnchor),
      fill.topAnchor.constraint(equalTo: topAnchor), fill.bottomAnchor.constraint(equalTo: bottomAnchor),
      heightAnchor.constraint(equalToConstant: 52), button.leadingAnchor.constraint(equalTo: fill.leadingAnchor, constant: 12),
      button.widthAnchor.constraint(equalToConstant: 24), button.centerYAnchor.constraint(equalTo: fill.centerYAnchor),
      button.heightAnchor.constraint(equalToConstant: 44), key.trailingAnchor.constraint(equalTo: fill.trailingAnchor, constant: -12), key.centerYAnchor.constraint(equalTo: fill.centerYAnchor),
      labels.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: 8), labels.trailingAnchor.constraint(equalTo: key.leadingAnchor, constant: -12), labels.centerYAnchor.constraint(equalTo: fill.centerYAnchor),
    ])
  }
  required init?(coder: NSCoder) { nil }
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let hit = super.hitTest(point) else { return nil }
    return hit === button || hit.isDescendant(of: button) ? hit : self
  }
  override func mouseDown(with event: NSEvent) { if button.isEnabled { button.performClick(nil) } }
  func update(selected: Bool, enabled: Bool) {
    button.state = selected ? .on : .off
    button.isEnabled = enabled
    fill.fillColor = selected ? .quaternarySystemFill : .clear
  }
}

@MainActor
final class MacQuestionView: NSStackView, NSTextFieldDelegate {
  var onAction: ((MacQuestionAction) -> Void)?
  var onReject: (() -> Void)?
  var rejectTitle = "" { didSet { skip.title = rejectTitle; skip.isHidden = rejectTitle.isEmpty } }
  private var draft: MacQuestionDraft?
  private var options: [MacInterruptionOption] = []
  private var custom: NSTextField?
  private let pages = NSSegmentedControl()
  private let submit = NSButton()
  private let skip = NSButton()

  init() {
    super.init(frame: .zero)
    orientation = .vertical
    alignment = .leading
    spacing = 12
    setHuggingPriority(.init(1), for: .horizontal)
    skip.isBordered = false
    skip.isHidden = true
    skip.target = self
    skip.action = #selector(rejected)
    skip.setAccessibilityIdentifier("question-skip")
    submit.bezelStyle = .rounded
    submit.controlSize = .large
    submit.target = self
    submit.action = #selector(submitted)
  }
  required init?(coder: NSCoder) { nil }

  func update(_ next: MacQuestionDraft, enabled: Bool, canSubmit: Bool) {
    let rebuild = draft?.meta != next.meta || draft?.page != next.page
    draft = next
    if rebuild { build(next) }
    pages.isEnabled = enabled
    skip.isEnabled = enabled
    pages.selectedSegment = next.page
    for (index, row) in options.enumerated() { row.update(selected: next.current.selected.contains(index), enabled: enabled) }
    custom?.isEnabled = enabled
    if custom?.stringValue != next.current.text { custom?.stringValue = next.current.text }
    let last = next.page == next.meta.questions.count - 1
    submit.setAccessibilityIdentifier(last ? "question-submit" : "question-next")
    submit.title = String(localized: String.LocalizationValue(last ? "question.submit" : "question.next"), bundle: .lodyData)
    let answered = !next.current.selected.isEmpty || !next.current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    submit.isEnabled = enabled && canSubmit && (last ? next.answers != nil : answered)
    submit.bezelColor = .lodyAccent
    submit.contentTintColor = .lodyAccentForeground
  }

  private func build(_ next: MacQuestionDraft) {
    arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() }
    options = []
    custom = nil
    let symbol = NSImageView(image: NSImage(systemSymbolName: "questionmark.bubble", accessibilityDescription: nil) ?? NSImage())
    symbol.contentTintColor = .secondaryLabelColor
    let status = NSTextField(labelWithString: String(localized: "question.title", bundle: .lodyData))
    status.font = .preferredFont(forTextStyle: .subheadline)
    status.textColor = .secondaryLabelColor
    let header = NSStackView(views: [symbol, status, NSView()])
    header.spacing = 8
    if next.meta.questions.count > 1 {
      pages.segmentCount = next.meta.questions.count
      for (index, question) in next.meta.questions.enumerated() { pages.setLabel(question.header, forSegment: index) }
      pages.trackingMode = .selectOne
      pages.controlSize = .small
      pages.target = self
      pages.action = #selector(pageChanged)
      pages.setAccessibilityIdentifier("question-pages")
      header.addArrangedSubview(pages)
    }
    add(header)
    let question = next.meta.questions[next.page]
    let title = NSTextField(wrappingLabelWithString: question.question)
    title.font = .systemFont(ofSize: 16, weight: .semibold)
    add(title)
    let rows = NSStackView()
    rows.orientation = .vertical
    rows.spacing = 4
    for (index, option) in question.options.enumerated() {
      let detail = [option.description, option.preview].compactMap { $0 }.joined(separator: "\n")
      let row = MacInterruptionOption(title: option.label, detail: detail, index: index, multiple: question.multiSelect) { [weak self] in self?.onAction?(.select(index)) }
      row.button.setAccessibilityIdentifier("question-option-\(index)")
      rows.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
      options.append(row)
    }
    if !options.isEmpty { add(rows) }
    if next.meta.allowsText(at: next.page) {
      let field: NSTextField = question.isSecret == true ? NSSecureTextField() : NSTextField()
      field.placeholderString = String(localized: "question.otherAnswer", bundle: .lodyData)
      field.setAccessibilityLabel(String(localized: "question.custom", bundle: .lodyData))
      field.setAccessibilityIdentifier("question-custom")
      field.delegate = self
      add(field)
      field.heightAnchor.constraint(equalToConstant: 32).isActive = true
      custom = field
    }
    add(NSStackView(views: [NSView(), skip, submit]))
  }
  private func add(_ child: NSView) { addArrangedSubview(child); child.widthAnchor.constraint(equalTo: widthAnchor).isActive = true }
  func controlTextDidChange(_ obj: Notification) { onAction?(.text(custom?.stringValue ?? "")) }
  @objc private func rejected() { if skip.isEnabled { onReject?() } }
  @objc private func submitted() {
    guard let draft, submit.isEnabled else { return }
    if draft.page < draft.meta.questions.count - 1 { onAction?(.page(draft.page + 1)) }
    else { onAction?(.submit) }
  }
  @objc private func pageChanged() { onAction?(.page(pages.selectedSegment)) }
}
