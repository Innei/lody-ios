import AppKit
import LodyData

@MainActor
final class MacQuestionView: NSStackView, NSTextFieldDelegate {
  var onAction: ((MacQuestionAction) -> Void)?
  private var draft: MacQuestionDraft?
  private var options: [NSButton] = []
  private var custom: NSTextField?
  private let pages = NSSegmentedControl()
  private let submit = NSButton()

  init() {
    super.init(frame: .zero)
    orientation = .vertical
    alignment = .leading
    spacing = 10
    setHuggingPriority(.init(1), for: .horizontal)
    submit.bezelStyle = .rounded
    submit.target = self
    submit.action = #selector(submitted)
    submit.setAccessibilityIdentifier("question-submit")
  }

  required init?(coder: NSCoder) { nil }

  func update(_ next: MacQuestionDraft, enabled: Bool, canSubmit: Bool) {
    let rebuild = draft?.meta != next.meta || draft?.page != next.page
    draft = next
    if rebuild { build(next) }
    pages.isEnabled = enabled
    pages.selectedSegment = next.page
    for (index, button) in options.enumerated() {
      button.state = next.current.selected.contains(index) ? .on : .off
      button.isEnabled = enabled
    }
    custom?.isEnabled = enabled
    if custom?.stringValue != next.current.text { custom?.stringValue = next.current.text }
    submit.isEnabled = enabled && canSubmit && next.answers != nil
  }

  private func build(_ next: MacQuestionDraft) {
    arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() }
    options = []
    custom = nil
    if next.meta.questions.count > 1 {
      pages.segmentCount = next.meta.questions.count
      for (index, question) in next.meta.questions.enumerated() { pages.setLabel(question.header, forSegment: index) }
      pages.trackingMode = .selectOne
      pages.target = self
      pages.action = #selector(pageChanged)
      pages.setAccessibilityIdentifier("question-pages")
      addArrangedSubview(pages)
    }
    let question = next.meta.questions[next.page]
    let title = NSTextField(wrappingLabelWithString: question.question)
    title.font = .preferredFont(forTextStyle: .headline)
    addArrangedSubview(title)
    title.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    for (index, option) in question.options.enumerated() {
      let button: NSButton
      if question.multiSelect { button = NSButton(checkboxWithTitle: option.label, target: self, action: #selector(selected(_:))) }
      else { button = NSButton(radioButtonWithTitle: option.label, target: self, action: #selector(selected(_:))) }
      button.tag = index
      button.setAccessibilityIdentifier("question-option-\(index)")
      button.cell?.wraps = true
      addArrangedSubview(button)
      options.append(button)
      let detail = [option.description, option.preview].compactMap { $0 }.joined(separator: "\n")
      if !detail.isEmpty {
        let label = NSTextField(wrappingLabelWithString: detail)
        label.textColor = .secondaryLabelColor
        label.font = .preferredFont(forTextStyle: .caption1)
        addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
      }
    }
    if next.meta.allowsText(at: next.page) {
      let field: NSTextField = question.isSecret == true ? NSSecureTextField() : NSTextField()
      field.placeholderString = String(localized: "question.otherAnswer", bundle: .lodyData)
      field.setAccessibilityLabel(String(localized: "question.custom", bundle: .lodyData))
      field.setAccessibilityIdentifier("question-custom")
      field.delegate = self
      addArrangedSubview(field)
      field.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
      custom = field
    }
    submit.title = String(localized: "question.submit", bundle: .lodyData)
    addArrangedSubview(submit)
  }

  func controlTextDidChange(_ obj: Notification) { onAction?(.text(custom?.stringValue ?? "")) }
  @objc private func selected(_ sender: NSButton) { onAction?(.select(sender.tag)) }
  @objc private func submitted() { onAction?(.submit) }
  @objc private func pageChanged() { onAction?(.page(pages.selectedSegment)) }
}
