#if DEBUG
import AppKit

/// A local, native design prototype. It does not submit cloud permissions or answers.
@MainActor
final class MacInterruptionStudy: NSView {
  enum Content { case approval, questions }
  var onFinish: (() -> Void)?
  private let content: Content
  private let glass = NSGlassEffectView()
  private let stack = NSStackView()
  private let questions = NSSegmentedControl(labels: ["Question 1", "Question 2"], trackingMode: .selectOne, target: nil, action: nil)
  private let body = NSStackView()
  private let next = NSButton(title: "Continue", target: nil, action: nil)
  private var picks: [Int: Int] = [:]
  private var answers: [Int: String] = [:]
  private var active = 0
  private var optionButtons: [NSButton] = []
  private var optionFills: [NSBox] = []
  private weak var custom: NSTextField?

  init(content: Content) {
    self.content = content
    super.init(frame: .zero)
    glass.style = .regular
    glass.cornerRadius = 20
    if #available(macOS 27, *) { glass.effectIsInteractive = true }
    glass.translatesAutoresizingMaskIntoConstraints = false
    addSubview(glass)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    stack.setHuggingPriority(.init(1), for: .horizontal)
    stack.setContentHuggingPriority(.init(1), for: .horizontal)
    glass.contentView = stack
    NSLayoutConstraint.activate([
      glass.leadingAnchor.constraint(equalTo: leadingAnchor),
      glass.trailingAnchor.constraint(equalTo: trailingAnchor),
      glass.topAnchor.constraint(equalTo: topAnchor),
      glass.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    let symbol = NSImageView(image: NSImage(systemSymbolName: content == .approval ? "hand.raised" : "questionmark.bubble", accessibilityDescription: nil) ?? NSImage())
    symbol.contentTintColor = .secondaryLabelColor
    symbol.symbolConfiguration = .init(pointSize: 13, weight: .regular)
    let status = label(content == .approval ? "Permission needed" : "Claude Code has a question", style: .subheadline, secondary: true)
    let header = NSStackView(views: [symbol, status, NSView()])
    header.spacing = 8
    if content == .questions {
      questions.segmentStyle = .automatic
      questions.controlSize = .small
      questions.selectedSegment = 0
      questions.target = self
      questions.action = #selector(questionChanged)
      questions.setAccessibilityIdentifier("permission-study-questions")
      header.addArrangedSubview(questions)
    }
    body.orientation = .vertical
    body.alignment = .leading
    body.spacing = 10
    body.setHuggingPriority(.init(1), for: .horizontal)
    let skip = NSButton(title: content == .approval ? "Cancel" : "Skip", target: self, action: #selector(finish))
    skip.bezelStyle = .accessoryBarAction
    skip.isBordered = false
    skip.isHidden = content == .approval
    skip.setAccessibilityIdentifier("permission-study-skip")
    next.bezelStyle = .rounded
    next.controlSize = .large
    next.bezelColor = .lodyAccent
    next.target = self
    next.action = #selector(continued)
    next.setAccessibilityIdentifier("permission-study-allow")
    let footer = NSStackView(views: [NSView(), skip, next])
    footer.spacing = 8
    stack.setViews([header, body, footer], in: .leading)
    for child in [header, body, footer] {
      child.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
    }
    setAccessibilityIdentifier("permission-study-glass")
    render()
  }

  required init?(coder: NSCoder) { nil }

  private func render() {
    body.arrangedSubviews.forEach { body.removeArrangedSubview($0); $0.removeFromSuperview() }
    optionButtons = []
    optionFills = []
    let title: String
    let detail: String
    let options: [(String, String)]
    if content == .approval {
      title = "Allow this file edit?"
      detail = "macOS/ViewControllers/Sidebar/SidebarViewController.swift"
      options = [
        ("Allow once", "Apply this change and continue the task."),
        ("Don't allow", "Keep the file unchanged."),
      ]
    } else if active == 0 {
      title = "How should sessions be organized?"
      detail = "Choose a starting point for the sidebar."
      options = [
        ("Group by project", "Keep conversations beside the code they belong to."),
        ("Show recent sessions", "List the latest conversations first."),
      ]
    } else {
      title = "How much detail should each row show?"
      detail = "This helps set the density of the session list."
      options = [
        ("Title and activity", "Include the latest agent activity under the title."),
        ("Compact titles", "Keep more conversations visible in the sidebar."),
      ]
    }
    let heading = label(title, style: .headline)
    heading.font = .systemFont(ofSize: 16, weight: .semibold)
    let explanation = label(detail, style: .subheadline, secondary: true)
    if content == .approval {
      explanation.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
      explanation.lineBreakMode = .byTruncatingMiddle
    }
    body.addArrangedSubview(heading)
    body.addArrangedSubview(explanation)
    heading.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
    explanation.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
    let rows = NSStackView()
    rows.orientation = .vertical
    rows.spacing = 4
    for (index, option) in options.enumerated() {
      let row = optionRow(index, title: option.0, detail: option.1)
      rows.addArrangedSubview(row)
      row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
    }
    body.addArrangedSubview(rows)
    rows.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
    if content == .questions {
      let input = NSTextField()
      input.placeholderString = "Or write another answer…"
      input.stringValue = answers[active] ?? ""
      input.font = .preferredFont(forTextStyle: .body)
      input.bezelStyle = .roundedBezel
      input.target = self
      input.action = #selector(customChanged)
      input.delegate = self
      input.setAccessibilityIdentifier("permission-study-custom")
      body.addArrangedSubview(input)
      NSLayoutConstraint.activate([
        input.widthAnchor.constraint(equalTo: body.widthAnchor),
        input.heightAnchor.constraint(equalToConstant: 32),
      ])
      custom = input
    }
    updateSelection()
  }

  private func optionRow(_ index: Int, title: String, detail: String) -> NSView {
    let fill = NSBox()
    fill.boxType = .custom
    fill.borderType = .noBorder
    fill.titlePosition = .noTitle
    fill.cornerRadius = 8
    fill.contentViewMargins = .zero
    fill.fillColor = .clear
    let button = NSButton(radioButtonWithTitle: "", target: self, action: #selector(picked(_:)))
    let attributed = NSMutableAttributedString(string: title + "\n", attributes: [.font: NSFont.preferredFont(forTextStyle: .body), .foregroundColor: NSColor.labelColor])
    attributed.append(NSAttributedString(string: detail, attributes: [.font: NSFont.preferredFont(forTextStyle: .subheadline), .foregroundColor: NSColor.secondaryLabelColor]))
    button.attributedTitle = attributed
    button.cell?.wraps = true
    button.cell?.lineBreakMode = .byWordWrapping
    button.tag = index
    button.setAccessibilityIdentifier("permission-study-option-\(index)")
    button.setAccessibilityLabel(title)
    button.setAccessibilityHelp(detail)
    button.translatesAutoresizingMaskIntoConstraints = false
    let key = label(String(index + 1), style: .caption1, secondary: true)
    key.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
    key.setAccessibilityElement(false)
    key.translatesAutoresizingMaskIntoConstraints = false
    fill.contentView?.addSubview(button)
    fill.contentView?.addSubview(key)
    NSLayoutConstraint.activate([
      fill.heightAnchor.constraint(equalToConstant: 52),
      button.leadingAnchor.constraint(equalTo: fill.leadingAnchor, constant: 12),
      button.trailingAnchor.constraint(lessThanOrEqualTo: key.leadingAnchor, constant: -12),
      button.centerYAnchor.constraint(equalTo: fill.centerYAnchor),
      button.heightAnchor.constraint(equalToConstant: 44),
      key.trailingAnchor.constraint(equalTo: fill.trailingAnchor, constant: -12),
      key.centerYAnchor.constraint(equalTo: fill.centerYAnchor),
    ])
    optionButtons.append(button)
    optionFills.append(fill)
    return fill
  }

  private func updateSelection() {
    for (index, button) in optionButtons.enumerated() {
      let selected = picks[active] == index && (answers[active] ?? "").isEmpty
      button.state = selected ? .on : .off
      optionFills[index].fillColor = selected ? .quaternarySystemFill : .clear
    }
    if content == .approval {
      next.isEnabled = picks[0] != nil
      next.title = "Continue"
    } else {
      next.title = active == 0 ? "Next" : "Send answer"
      let answered: (Int) -> Bool = { [self] index in
        picks[index] != nil || !(answers[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      }
      next.isEnabled = active == 0 ? answered(active) : (0...1).allSatisfy(answered)
    }
  }

  @objc private func picked(_ sender: NSButton) {
    picks[active] = sender.tag
    answers[active] = nil
    custom?.stringValue = ""
    updateSelection()
  }
  @objc private func customChanged() {
    answers[active] = custom?.stringValue ?? ""
    updateSelection()
  }
  @objc private func questionChanged() {
    active = questions.selectedSegment
    render()
  }
  @objc private func continued() {
    guard next.isEnabled else { return }
    if content == .questions, active == 0 {
      active = 1
      questions.selectedSegment = 1
      render()
    } else { finish() }
  }
  @objc private func finish() { onFinish?() }

  private func label(_ text: String, style: NSFont.TextStyle, secondary: Bool = false) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .preferredFont(forTextStyle: style)
    field.textColor = secondary ? .secondaryLabelColor : .labelColor
    field.lineBreakMode = .byTruncatingTail
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
  }
}

extension MacInterruptionStudy: NSTextFieldDelegate {
  func controlTextDidChange(_ obj: Notification) { customChanged() }
}
#endif
