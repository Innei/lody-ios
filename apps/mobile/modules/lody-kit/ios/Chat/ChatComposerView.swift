import UIKit
import UniformTypeIdentifiers

private struct ChatComposerState: Decodable {
  var mentionItems: [ChatMentionItem]?
  var editable = true
  var canSend = false
  var sending = false
  var running: Bool?
  var canStop: Bool?
  var stopping: Bool?
  var controlling: Bool?
  var steerID: String?
  var steerInterrupts: Bool?
  var notice = ""
  var reconnect = false
  var placeholder = LodyStrings.text("native.chat.composer.placeholder")
}

struct ChatQueuedDraft: Equatable {
  let id: String
  let text: String
  var canSteer = true
  var attachments: [String] = []

  static func rowHeight(_ draft: ChatQueuedDraft) -> CGFloat {
    let caption = draft.attachments.isEmpty ? 0 : ceil(UIFont.dynamic(of: 12).lineHeight) + 2
    return max(44, ceil(UIFont.dynamic(of: 15).lineHeight) + caption + 10)
  }

  static func panelHeight(_ drafts: [ChatQueuedDraft]) -> CGFloat {
    drafts.prefix(3).reduce(0) { $0 + rowHeight($1) }
  }
}

private final class ChatQueueView: UIVisualEffectView {
  private let scroll = UIScrollView()
  private let stack = UIStackView()
  private var rendered: [ChatQueuedDraft] = []
  private var buttons: [String: UIButton] = [:]
  private var rows: [String: UIView] = [:]
  var onSteer: ((String) -> Void)?

  init() {
    super.init(effect: nil)
    accessibilityIdentifier = "session-queue"
    let glass = UIGlassEffect(style: .regular)
    glass.isInteractive = true
    effect = glass
    cornerConfiguration = .corners(radius: .fixed(20))
    stack.axis = .vertical
    scroll.addSubview(stack)
    contentView.addSubview(scroll)
    scroll.translatesAutoresizingMaskIntoConstraints = false
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: contentView.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
      stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
      stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
    ])
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func render(_ drafts: [ChatQueuedDraft], enabled: Bool, steeringID: String, firstOnly: Bool) {
    if rendered != drafts {
      // A row that leaves the queue is on its way into the transcript: hand its
      // frame to the send animation before the row disappears.
      for draft in rendered where !drafts.contains(where: { $0.id == draft.id }) {
        guard let row = rows[draft.id], !draft.text.isEmpty else { continue }
        ChatSendHandoff.begin(id: draft.id, text: draft.text, source: row, straight: true)
      }
      rendered = drafts
      stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
      buttons.removeAll()
      rows.removeAll()
      for draft in drafts {
        let text = UILabel()
        text.text = draft.text.isEmpty ? LodyStrings.text("native.chat.row.queuedAttachmentsOnly") : draft.text
        text.font = .dynamic(of: 15)
        text.textColor = draft.text.isEmpty ? .tertiaryLabel : .secondaryLabel
        text.accessibilityIdentifier = draft.id + ":queued"
        text.accessibilityLabel = ([LodyStrings.text("native.chat.row.queued") + ": " + draft.text] + draft.attachments)
          .filter { !$0.isEmpty }.joined(separator: ", ")
        let body = UIStackView(arrangedSubviews: [text])
        body.axis = .vertical
        body.spacing = 2
        if !draft.attachments.isEmpty { body.addArrangedSubview(Self.caption(draft.attachments)) }
        let button = UIButton(type: .system)
        button.configuration = .plain()
        button.setImage(
          UIImage(systemName: "arrow.up.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)),
          for: .normal
        )
        button.accessibilityIdentifier = draft.id + ":steer"
        button.accessibilityLabel = LodyStrings.text("native.chat.composer.steer") + ": " + draft.text
        button.addAction(UIAction { [weak self] _ in self?.onSteer?(draft.id) }, for: .touchUpInside)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [body, button])
        row.alignment = .center
        row.spacing = 8
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 4, leading: 16, bottom: 4, trailing: 2)
        if !stack.arrangedSubviews.isEmpty {
          let separator = UIView()
          separator.backgroundColor = .separator
          separator.translatesAutoresizingMaskIntoConstraints = false
          row.addSubview(separator)
          NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: row.topAnchor),
            separator.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
          ])
        }
        stack.addArrangedSubview(row)
        row.heightAnchor.constraint(equalToConstant: ChatQueuedDraft.rowHeight(draft)).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        buttons[draft.id] = button
        rows[draft.id] = row
      }
    }
    let first = drafts.first(where: \.canSteer)?.id
    for draft in drafts {
      let waiting = steeringID == draft.id || !draft.canSteer
      buttons[draft.id]?.isEnabled = enabled && draft.canSteer && (!firstOnly || draft.id == first)
      buttons[draft.id]?.accessibilityHint = waiting ? LodyStrings.text("native.chat.composer.steering") : nil
    }
    isHidden = drafts.isEmpty
  }

  private static func caption(_ attachments: [String]) -> UIView {
    let clip = UIImageView(image: UIImage(systemName: "paperclip", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .regular)))
    clip.tintColor = .tertiaryLabel
    clip.setContentHuggingPriority(.required, for: .horizontal)
    let names = UILabel()
    names.text = attachments.joined(separator: " · ")
    names.font = .dynamic(of: 12)
    names.textColor = .tertiaryLabel
    names.lineBreakMode = .byTruncatingMiddle
    let line = UIStackView(arrangedSubviews: [clip, names])
    line.alignment = .center
    line.spacing = 4
    return line
  }
}

private final class ChatComposerInput: UITextView {
  var onPasteItems: (([NSItemProvider]) -> Bool)?

  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(paste(_:)), isEditable, UIPasteboard.general.numberOfItems > 0 { return true }
    return super.canPerformAction(action, withSender: sender)
  }

  override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
    ChatAttachment.canPaste(itemProviders) || super.canPaste(itemProviders)
  }

  override func paste(itemProviders: [NSItemProvider]) {
    guard onPasteItems?(itemProviders) == true else {
      super.paste(itemProviders: itemProviders)
      return
    }
  }

  override func paste(_ sender: Any?) {
    guard onPasteItems?(UIPasteboard.general.itemProviders) == true else {
      super.paste(sender)
      return
    }
  }
}

private final class ChatComposerProgressView: UIView {
  private let arc = CAShapeLayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "session-action-progress"
    isUserInteractionEnabled = false
    arc.fillColor = UIColor.clear.cgColor
    arc.strokeColor = UIColor.white.cgColor
    arc.lineCap = .round
    arc.lineWidth = 2.25
    layer.addSublayer(arc)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    arc.frame = bounds
    let inset = arc.lineWidth / 2
    arc.path = UIBezierPath(
      arcCenter: CGPoint(x: bounds.midX, y: bounds.midY),
      radius: max(0, min(bounds.width, bounds.height) / 2 - inset),
      startAngle: -.pi / 2,
      endAngle: .pi,
      clockwise: true
    ).cgPath
  }

  func startAnimating() {
    isHidden = false
    guard layer.animation(forKey: "composer.loading.rotation") == nil else { return }
    let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
    rotation.fromValue = 0
    rotation.toValue = CGFloat.pi * 2
    rotation.duration = 0.8
    rotation.repeatCount = .infinity
    rotation.timingFunction = CAMediaTimingFunction(name: .linear)
    layer.add(rotation, forKey: "composer.loading.rotation")
  }

  func stopAnimating() {
    isHidden = true
    layer.removeAnimation(forKey: "composer.loading.rotation")
  }
}

private enum ChatComposerActionMode {
  case send
  case loading
  case stop

  var color: UIColor {
    switch self {
    case .send: .systemBlue
    case .loading: .systemGray
    case .stop: .systemRed
    }
  }

  var symbolName: String {
    switch self {
    case .send, .loading: "arrow.up"
    case .stop: "stop.fill"
    }
  }
}

private final class ChatComposerActionVisual: UIView {
  private let content = UIView()
  private let symbol = UIImageView()
  private let progress = ChatComposerProgressView()
  private var mode: ChatComposerActionMode?

  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "session-action-visual"
    isUserInteractionEnabled = false
    layer.cornerCurve = .continuous
    content.accessibilityIdentifier = "session-action-content"
    content.isUserInteractionEnabled = false
    symbol.contentMode = .center
    symbol.tintColor = .white
    addSubview(content)
    content.addSubview(symbol)
    content.addSubview(progress)
    content.translatesAutoresizingMaskIntoConstraints = false
    symbol.translatesAutoresizingMaskIntoConstraints = false
    progress.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      content.topAnchor.constraint(equalTo: topAnchor),
      content.bottomAnchor.constraint(equalTo: bottomAnchor),
      content.leadingAnchor.constraint(equalTo: leadingAnchor),
      content.trailingAnchor.constraint(equalTo: trailingAnchor),
      symbol.topAnchor.constraint(equalTo: content.topAnchor),
      symbol.bottomAnchor.constraint(equalTo: content.bottomAnchor),
      symbol.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      symbol.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      progress.centerXAnchor.constraint(equalTo: content.centerXAnchor),
      progress.centerYAnchor.constraint(equalTo: content.centerYAnchor),
      progress.widthAnchor.constraint(equalToConstant: 15),
      progress.heightAnchor.constraint(equalToConstant: 15),
    ])
    render(.send)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.width / 2
  }

  func render(_ nextMode: ChatComposerActionMode) {
    guard mode != nextMode else { return }
    let shouldAnimate = mode != nil && window != nil
    mode = nextMode
    guard shouldAnimate else {
      backgroundColor = nextMode.color
      applyContent(nextMode)
      return
    }

    let duration = UIAccessibility.isReduceMotionEnabled ? 0.18 : 0.2
    UIView.transition(
      with: content,
      duration: duration,
      options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent]
    ) {
      self.applyContent(nextMode)
    }
    UIView.animate(
      withDuration: duration,
      delay: 0,
      options: [.beginFromCurrentState, .curveEaseInOut]
    ) {
      self.backgroundColor = nextMode.color
    }
    guard !UIAccessibility.isReduceMotionEnabled else { return }
    UIView.animateKeyframes(
      withDuration: duration,
      delay: 0,
      options: [.beginFromCurrentState, .calculationModeCubic]
    ) {
      UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.45) {
        self.content.transform = CGAffineTransform(scaleX: 0.72, y: 0.72)
      }
      UIView.addKeyframe(withRelativeStartTime: 0.45, relativeDuration: 0.55) {
        self.content.transform = .identity
      }
    }
  }

  private func applyContent(_ mode: ChatComposerActionMode) {
    symbol.image = UIImage(
      systemName: mode.symbolName,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
    )
    symbol.isHidden = mode == .loading
    if mode == .loading { progress.startAnimating() } else { progress.stopAnimating() }
  }
}

final class ChatComposerView: UIView, UITextViewDelegate {
  private let composer = UIVisualEffectView(effect: nil)
  private let inputSurface = UIVisualEffectView(effect: nil)
  private let input = ChatComposerInput()
  private let hint = UILabel()
  private let notice = UIButton(type: .system)
  private let send = UIButton(type: .system)
  private let sendVisual = ChatComposerActionVisual()
  private let sendFeedback = UIImpactFeedbackGenerator(style: .medium)
  private let attach = UIButton(type: .system)
  private let attachSurface = UIVisualEffectView(effect: nil)
  private let accessoryBar = UIView()
  private let modelButton = UIButton(type: .system)
  private weak var optionsPopover: ChatComposerModelPanel?
  private let attachmentBar = ChatAttachmentBar()
  private var attachments: [ChatAttachment] = []
  private let filePicker = ChatAttachmentPicker()
  private let libraryPicker = ChatPhotoLibraryPicker()
  private var inputHeight: NSLayoutConstraint!
  private var accessoryHeight: NSLayoutConstraint!
  private var hintLeading: NSLayoutConstraint!
  private var hintTop: NSLayoutConstraint!
  private var noticeHeight: NSLayoutConstraint!
  private var attachmentHeight: NSLayoutConstraint!
  private let mentionPanel = ChatMentionPanel(frame: .zero)
  private var separateMentionItems: [ChatMentionItem]?
  private var usesSeparateMentionItems = false
  private var activeMentionItems: [ChatMentionItem]? { usesSeparateMentionItems ? separateMentionItems : state.mentionItems }
  func setMentionItems(_ json: String) {
    usesSeparateMentionItems = true
    separateMentionItems = try? JSONDecoder().decode([ChatMentionItem].self, from: Data(json.utf8))
    updateComposer()
  }
  private let mentionButton = UIButton(type: .system)
  private var mentionHeight: NSLayoutConstraint!
  private let queueView = ChatQueueView()
  private var queueHeight: NSLayoutConstraint!
  private var queuedDrafts: [ChatQueuedDraft] = []
  private var state = ChatComposerState()
  private var composerOptions = ChatComposerOptions()
  private var composerExpanded = false
  private var pendingDraft: (text: String, attachments: [ChatAttachment])?
  private var lastRestoreToken = 0
  private var hasInitialDraft = false
  private var hasInitialAttachments = false
  private var lastClearToken = 0
  var onSend: (([String: Any]) -> Void)?
  var onStop: (() -> Void)?
  var onSteer: ((String) -> Void)?
  var queuesSubmission: Bool { state.running == true || !queuedDrafts.isEmpty }
  var onReconnect: (() -> Void)?
  var onMentionBrowse: (([String: String]) -> Void)?
  private var mentionResultID = ""
  private var mentionNeedsFocus = false
  var onComposerOptionChange: (([String: Any]) -> Void)?
  var onDraftChange: ((String) -> Void)?
  var onHeightChange: ((CGFloat) -> Void)?
  var displayError: String? { didSet { updateComposer() } }
  private var measuredWidth: CGFloat = 0
  private lazy var surfaceLayout: any ChatComposerSurfaceLayout = ChatComposerLiquidGlassSurfaceLayout(
    container: composer,
    inputSurface: inputSurface,
    attachSurface: attachSurface,
    attachButton: attach
  )

  func setInputIdentifier(_ id: String) { input.accessibilityIdentifier = id }

  func attachScrollEdge(to scrollView: UIScrollView?) {
    let existing = composer.interactions.compactMap { $0 as? UIScrollEdgeElementContainerInteraction }.first
    guard scrollView != nil || existing != nil else { return }
    let edge = existing ?? UIScrollEdgeElementContainerInteraction()
    edge.scrollView = scrollView
    edge.edge = .bottom
    if edge.view == nil { composer.addInteraction(edge) }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    if abs(input.bounds.width - measuredWidth) > 0.5 {
      measuredWidth = input.bounds.width
      updateComposer()
    }
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
    input.font = .dynamic(of: 17, compatibleWith: traitCollection)
    hint.font = input.font
    notice.titleLabel?.font = .dynamic(of: 13, compatibleWith: traitCollection)
    updateComposer()
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    composer.backgroundColor = .clear
    input.backgroundColor = .clear
    input.font = .dynamic(of: 17)
    input.textColor = .label
    input.textContainerInset = UIEdgeInsets(top: 13, left: 16, bottom: 13, right: 46)
    input.delegate = self
    input.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [UTType.item.identifier])
    input.onPasteItems = { [weak self] providers in
      guard let self, self.state.editable else { return false }
      return ChatAttachment.paste(providers) { [weak self] in self?.addAttachments($0) }
    }
    input.accessibilityIdentifier = "session-input"
    input.accessibilityLabel = LodyStrings.text("native.chat.composer.input")
    hint.text = state.placeholder
    hint.font = input.font
    hint.textColor = .placeholderText
    hint.isUserInteractionEnabled = false
    hint.isAccessibilityElement = false
    send.tintColor = .systemBlue
    sendVisual.translatesAutoresizingMaskIntoConstraints = false
    send.addSubview(sendVisual)
    NSLayoutConstraint.activate([
      sendVisual.centerXAnchor.constraint(equalTo: send.centerXAnchor),
      sendVisual.centerYAnchor.constraint(equalTo: send.centerYAnchor),
      sendVisual.widthAnchor.constraint(equalToConstant: 30),
      sendVisual.heightAnchor.constraint(equalToConstant: 30),
    ])
    send.accessibilityLabel = LodyStrings.text("native.chat.composer.send")
    send.accessibilityIdentifier = "session-send"
    send.addTarget(self, action: #selector(submit), for: .touchUpInside)
    NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    attach.setImage(UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
    attach.configuration = .plain()
    attach.configuration?.cornerStyle = .capsule
    attach.tintColor = .label
    attach.accessibilityLabel = LodyStrings.text("native.chat.composer.attach")
    attach.accessibilityIdentifier = "session-attach"
    attach.showsMenuAsPrimaryAction = true
    attach.menu = UIMenu(children: [
      UIAction(title: LodyStrings.text("native.chat.composer.recentPhotos"), image: UIImage(systemName: "photo")) { [weak self] _ in self?.presentRecentPhotos() },
      UIAction(title: LodyStrings.text("native.chat.composer.photoLibrary"), image: UIImage(systemName: "photo.on.rectangle.angled")) { [weak self] _ in
        guard let self, let controller = self.presenter() else { return }
        self.libraryPicker.present(from: controller)
      },
      UIAction(title: LodyStrings.text("native.chat.composer.files"), image: UIImage(systemName: "folder")) { [weak self] _ in
        guard let self, let controller = self.presenter() else { return }
        self.filePicker.files(from: controller)
      },
    ])
    modelButton.accessibilityIdentifier = "session-model"
    modelButton.addTarget(self, action: #selector(presentComposerOptions), for: .touchUpInside)
    modelButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    filePicker.onPick = { [weak self] picked in self?.addAttachments(picked) }
    libraryPicker.onPick = { [weak self] picked in self?.addAttachments(picked) }
    attachmentBar.onPreview = { [weak self] id in
      guard let self, let index = self.attachments.firstIndex(where: { $0.id == id }), let controller = self.presenter() else { return }
      controller.present(ChatAttachmentPreview(self.attachments, index: index), animated: true)
    }
    attachmentBar.onRemove = { [weak self] id in
      guard let self else { return }
      self.attachments.removeAll { $0.id == id }
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
      self.updateComposer()
    }
    notice.titleLabel?.font = .dynamic(of: 13)
    notice.titleLabel?.numberOfLines = 0
    notice.addTarget(self, action: #selector(reconnect), for: .touchUpInside)
    mentionButton.setImage(UIImage(systemName: "at", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)), for: .normal)
    mentionButton.tintColor = .label
    mentionButton.accessibilityLabel = LodyStrings.text("native.chat.mention.open")
    mentionButton.accessibilityIdentifier = "session-mention"
    mentionButton.addTarget(self, action: #selector(openMentions), for: .touchUpInside)
    mentionPanel.onChange = { [weak self] in self?.updateComposer() }
    mentionPanel.onBrowse = { [weak self] in self?.onMentionBrowse?($0) }
    addSubview(composer)
    composer.contentView.addSubview(mentionPanel)
    composer.contentView.addSubview(queueView)
    queueView.onSteer = { [weak self] in self?.onSteer?($0) }
    composer.contentView.addSubview(notice)
    composer.contentView.addSubview(attachmentBar)
    composer.contentView.addSubview(attachSurface)
    composer.contentView.addSubview(inputSurface)
    attachSurface.contentView.addSubview(attach)
    for view in [input, hint, accessoryBar, modelButton, mentionButton, send] {
      inputSurface.contentView.addSubview(view)
    }
    for view in [composer, mentionPanel, mentionButton, queueView, inputSurface, attachSurface, notice, attachmentBar, input, hint, accessoryBar, send, attach, modelButton] {
      view.translatesAutoresizingMaskIntoConstraints = false
    }
    inputHeight = input.heightAnchor.constraint(equalToConstant: 48)
    accessoryHeight = accessoryBar.heightAnchor.constraint(equalToConstant: 0)
    hintLeading = hint.leadingAnchor.constraint(equalTo: input.leadingAnchor, constant: 21)
    hintTop = hint.topAnchor.constraint(equalTo: input.topAnchor, constant: 13)
    noticeHeight = notice.heightAnchor.constraint(equalToConstant: 0)
    attachmentHeight = attachmentBar.heightAnchor.constraint(equalToConstant: 0)
    queueHeight = queueView.heightAnchor.constraint(equalToConstant: 0)
    mentionHeight = mentionPanel.heightAnchor.constraint(equalToConstant: 0)
    surfaceLayout.activate()
    NSLayoutConstraint.activate([
      composer.topAnchor.constraint(equalTo: topAnchor),
      composer.leadingAnchor.constraint(equalTo: leadingAnchor),
      composer.trailingAnchor.constraint(equalTo: trailingAnchor),
      composer.bottomAnchor.constraint(equalTo: bottomAnchor),
      mentionPanel.topAnchor.constraint(equalTo: composer.topAnchor),
      mentionPanel.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 16),
      mentionPanel.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -16), mentionHeight,
      queueView.topAnchor.constraint(equalTo: mentionPanel.bottomAnchor),
      queueView.leadingAnchor.constraint(equalTo: inputSurface.leadingAnchor),
      queueView.trailingAnchor.constraint(equalTo: inputSurface.trailingAnchor), queueHeight,
      notice.topAnchor.constraint(equalTo: queueView.bottomAnchor), notice.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 20),
      notice.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -20), noticeHeight,
      attachmentBar.topAnchor.constraint(equalTo: notice.bottomAnchor),
      attachmentBar.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 16),
      attachmentBar.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -16), attachmentHeight,
      inputSurface.topAnchor.constraint(equalTo: attachmentBar.bottomAnchor, constant: 8),
      attachSurface.widthAnchor.constraint(equalToConstant: 44), attachSurface.heightAnchor.constraint(equalToConstant: 44),
      inputSurface.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -16),
      inputSurface.bottomAnchor.constraint(equalTo: composer.bottomAnchor, constant: -8),
      attach.topAnchor.constraint(equalTo: attachSurface.contentView.topAnchor),
      attach.bottomAnchor.constraint(equalTo: attachSurface.contentView.bottomAnchor),
      attach.leadingAnchor.constraint(equalTo: attachSurface.contentView.leadingAnchor),
      attach.trailingAnchor.constraint(equalTo: attachSurface.contentView.trailingAnchor),
      input.topAnchor.constraint(equalTo: inputSurface.contentView.topAnchor),
      input.leadingAnchor.constraint(equalTo: inputSurface.contentView.leadingAnchor),
      input.trailingAnchor.constraint(equalTo: inputSurface.contentView.trailingAnchor), inputHeight,
      accessoryBar.topAnchor.constraint(equalTo: input.bottomAnchor),
      accessoryBar.leadingAnchor.constraint(equalTo: inputSurface.contentView.leadingAnchor),
      accessoryBar.trailingAnchor.constraint(equalTo: inputSurface.contentView.trailingAnchor),
      accessoryBar.bottomAnchor.constraint(equalTo: inputSurface.contentView.bottomAnchor), accessoryHeight,
      hintLeading, hintTop,
      hint.trailingAnchor.constraint(lessThanOrEqualTo: send.leadingAnchor),
      send.trailingAnchor.constraint(equalTo: inputSurface.contentView.trailingAnchor, constant: -2),
      send.bottomAnchor.constraint(equalTo: inputSurface.contentView.bottomAnchor, constant: -2),
      send.widthAnchor.constraint(equalToConstant: 44), send.heightAnchor.constraint(equalToConstant: 44),
      mentionButton.leadingAnchor.constraint(equalTo: inputSurface.leadingAnchor, constant: 52),
      mentionButton.centerYAnchor.constraint(equalTo: send.centerYAnchor),
      mentionButton.widthAnchor.constraint(equalToConstant: 44), mentionButton.heightAnchor.constraint(equalToConstant: 44),
      modelButton.leadingAnchor.constraint(greaterThanOrEqualTo: inputSurface.contentView.leadingAnchor, constant: 2),
      modelButton.centerYAnchor.constraint(equalTo: send.centerYAnchor),
      modelButton.heightAnchor.constraint(equalToConstant: 44),
      modelButton.trailingAnchor.constraint(equalTo: send.leadingAnchor, constant: -2),
    ])
    updateComposer()
  }

  func setInitialDraft(_ text: String) {
    guard !hasInitialDraft else { return }
    hasInitialDraft = true
    guard pendingDraft == nil else { return }
    input.text = text
    updateComposer()
  }
  private var lastAppendedDraftID = ""
  func appendDraft(_ json: String) {
    guard let data = json.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
          let id = value["id"], !id.isEmpty, id != lastAppendedDraftID,
          let text = value["text"], !text.isEmpty else { return }
    lastAppendedDraftID = id
    // Keep the user's existing text AND attachments. Sending remains explicit.
    input.text = [input.text ?? "", text].filter { !$0.isEmpty }.joined(separator: "\n\n")
    input.selectedRange = NSRange(location: (input.text as NSString).length, length: 0)
    updateComposer()
    saveDraft()
  }
  func setStoredDraft(_ text: String) {
    guard !text.isEmpty, input.text.isEmpty else { return }
    input.text = text
    updateComposer()
  }
  private func saveDraft() {
    onDraftChange?(input.text ?? "")
  }
  @objc private func appDidEnterBackground() { saveDraft() }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      saveDraft()
      optionsPopover?.dismiss(animated: false)
    }
    else if mentionNeedsFocus { focusAfterMentionPicker() }
  }
  func setInitialAttachments(_ json: String) {
    guard !hasInitialAttachments else { return }
    struct DraftAttachment: Decodable {
      let id: String
      let name: String
      let uri: URL
      let kind: String
    }
    guard let drafts = try? JSONDecoder().decode([DraftAttachment].self, from: Data(json.utf8)),
      drafts.allSatisfy({ $0.uri.isFileURL && ($0.kind == "image" || $0.kind == "file") }) else { return }
    hasInitialAttachments = true
    guard pendingDraft == nil else { return }
    attachments = drafts.map { ChatAttachment(id: $0.id, name: $0.name, url: $0.uri, isImage: $0.kind == "image") }
    updateComposer()
  }
  func clearDraft(token: Int) {
    guard token > lastClearToken else { return }
    lastClearToken = token
    guard pendingDraft != nil else { return }
    acknowledgedSendID = pendingSendID
    pendingDraft = nil
    pendingSendID = nil
    updateComposer()
    saveDraft()
  }
  func clearPendingSend(id: String) {
    guard pendingSendID == id else { return }
    acknowledgedSendID = id
    pendingDraft = nil
    pendingSendID = nil
    updateComposer()
    saveDraft()
  }
  func restoreDraft(token: Int) {
    guard token > lastRestoreToken else { return }
    lastRestoreToken = token
    let id = pendingSendID ?? UUID().uuidString.lowercased()
    ChatSendHandoff.cancel(id: id)
    pendingSendID = nil
    if let draft = pendingDraft {
      if (input.text ?? "").isEmpty && attachments.isEmpty {
        input.text = draft.text
        attachments = draft.attachments
      } else {
        failedDraft = ChatPendingSend(id: id, text: draft.text, attachments: draft.attachments.map { item in
          ChatPendingSend.Attachment(id: item.id, name: item.name, uri: item.url.absoluteString, kind: item.isImage ? "image" : "file")
        }, status: "", failed: true)
      }
      pendingDraft = nil
    }
    updateComposer()
  }
  private var pendingSendID: String?
  private var acknowledgedSendID: String?
  private var restoredSendID: String?
  private var failedDraft: ChatPendingSend?

  func setPendingSend(_ pending: ChatPendingSend) {
    guard pending.id != restoredSendID, pending.id != acknowledgedSendID else { return }
    if pending.failed == true {
      pendingDraft = nil
      pendingSendID = nil
      updateComposer()
      return
    }
    guard pendingSendID != pending.id else { return }
    pendingSendID = pending.id
    pendingDraft = (pending.text, pending.attachments.compactMap { item in
      guard let url = URL(string: item.uri), url.isFileURL else { return nil }
      return ChatAttachment(id: item.id, name: item.name, url: url, isImage: item.kind == "image")
    })
    updateComposer()
  }

  private func takeDraft() {
    guard pendingDraft == nil else { return }
    pendingDraft = (input.text ?? "", attachments)
    input.text = ""
    attachments = []
  }
  private func presentRecentPhotos() {
    guard let controller = presenter() else { return }
    let sheet = ChatAttachmentSheet()
    sheet.onPick = { [weak self] picked in self?.addAttachments(picked) }
    controller.present(sheet, animated: true)
  }
  private func addAttachments(_ picked: [ChatAttachment]) {
    attachments += picked.filter { new in !attachments.contains { $0.id == new.id } }
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    updateComposer()
  }
  private func presenter() -> UIViewController? {
    var responder: UIResponder? = next
    while let current = responder {
      if let controller = current as? UIViewController { return controller.presentedViewController ?? controller }
      responder = current.next
    }
    return window?.rootViewController
  }
  func setComposerState(_ json: String) {
    guard let value = try? JSONDecoder().decode(ChatComposerState.self, from: Data(json.utf8)) else { return }
    if value.sending && !state.sending { takeDraft() }
    state = value
    updateComposer()
  }
  func setComposerOptions(_ json: String) {
    guard let value = try? JSONDecoder().decode(ChatComposerOptions.self, from: Data(json.utf8)) else { return }
    composerOptions = value
    updateComposerOptions()
  }
  func setQueue(_ drafts: [ChatQueuedDraft]) {
    guard queuedDrafts != drafts else { return }
    queuedDrafts = drafts
    updateComposer()
  }
  private func updateComposer() {
    mentionPanel.update(input: input, items: activeMentionItems ?? [], enabled: activeMentionItems != nil)
    mentionHeight.constant = mentionPanel.panelHeight
    mentionButton.isHidden = activeMentionItems == nil || !input.isFirstResponder
    mentionButton.isEnabled = state.editable && !state.sending && pendingDraft == nil
    let sending = state.sending || pendingDraft != nil
    let expanded = input.isFirstResponder
    let expansionChanged = composerExpanded != expanded
    if expansionChanged && window != nil { layoutIfNeeded() }
    composerExpanded = expanded
    surfaceLayout.update(isFocused: expanded)
    input.isEditable = state.editable
    attach.isEnabled = state.editable && !sending
    attach.alpha = attach.isEnabled ? 1 : 0.5
    attachmentBar.isUserInteractionEnabled = state.editable && !sending
    attachmentBar.render(attachments)
    attachmentHeight.constant = attachments.isEmpty ? 0 : 42
    hint.text = state.placeholder
    hint.isHidden = !input.text.isEmpty
    let hasContent = !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    let stop = !hasContent && state.running == true
    var label = "native.chat.composer.send"
    if stop { label = "native.chat.composer.stop" }
    let loading = sending || state.stopping == true
    if sending { label = "native.chat.composer.sending" }
    if state.stopping == true { label = "native.chat.composer.stopping" }
    let actionable = stop ? state.canStop == true : state.canSend && hasContent
    send.isEnabled = failedDraft == nil && displayError == nil && state.editable && actionable && !loading && state.controlling != true
    if send.isEnabled && !stop { sendFeedback.prepare() }
    send.accessibilityLabel = LodyStrings.text(label)
    send.accessibilityIdentifier = stop ? "session-stop" : "session-send"
    var actionMode: ChatComposerActionMode = stop ? .stop : .send
    if loading { actionMode = .loading }
    sendVisual.render(actionMode)
    sendVisual.isHidden = false
    sendVisual.alpha = send.isEnabled || loading ? 1 : 0.35
    queueHeight.constant = ChatQueuedDraft.panelHeight(queuedDrafts)
    queueView.render(queuedDrafts, enabled: state.canStop == true && !sending && state.controlling != true, steeringID: state.steerID ?? "", firstOnly: state.steerInterrupts == true)
    let noticeText = failedDraft == nil ? (displayError ?? state.notice) : LodyStrings.text("native.chat.composer.failedDraft")
    let canReconnect = failedDraft != nil || displayError != nil || state.reconnect
    notice.setTitle(noticeText, for: .normal)
    notice.setTitleColor(canReconnect ? .systemBlue : .secondaryLabel, for: .normal)
    notice.isUserInteractionEnabled = canReconnect
    notice.accessibilityTraits = canReconnect ? .button : .staticText
    let noticeSize = notice.sizeThatFits(CGSize(width: max(1, bounds.width - 40), height: .greatestFiniteMagnitude))
    noticeHeight.constant = noticeText.isEmpty ? 0 : max(44, noticeSize.height + 12)
    accessoryHeight.constant = expanded ? 44 : 0
    let verticalInset = expanded ? 13 : max(0, (48 - input.font!.lineHeight) / 2)
    input.textContainerInset = UIEdgeInsets(top: verticalInset, left: 16, bottom: verticalInset, right: expanded ? 16 : 46)
    hintLeading.constant = 21
    hintTop.constant = verticalInset
    let height = input.sizeThatFits(CGSize(width: max(1, input.bounds.width), height: .greatestFiniteMagnitude)).height
    inputHeight.constant = min(ChatMessageContent.maximumCollapsedHeight, max(expanded ? 68 : 48, height))
    input.isScrollEnabled = height > ChatMessageContent.maximumCollapsedHeight
    updateComposerOptions()
    onHeightChange?(mentionHeight.constant + queueHeight.constant + noticeHeight.constant + attachmentHeight.constant + inputHeight.constant + accessoryHeight.constant + 16)
    setNeedsLayout()
    if expansionChanged {
      if window != nil && !UIAccessibility.isReduceMotionEnabled {
        UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
          self.layoutIfNeeded()
        } completion: { finished in
          if finished && self.composerExpanded == expanded { self.surfaceLayout.completeTransition() }
        }
      } else {
        layoutIfNeeded()
        surfaceLayout.completeTransition()
      }
    }
  }
  private func updateComposerOptions() {
    modelButton.isHidden = !composerExpanded || composerOptions.models.isEmpty
    modelButton.isEnabled = state.editable && !state.sending && pendingDraft == nil
    let title = NSMutableAttributedString(string: composerOptions.modelTitle, attributes: [.foregroundColor: UIColor.label])
    if !composerOptions.efforts.isEmpty || !composerOptions.effort.isEmpty {
      title.append(NSAttributedString(string: " " + composerOptions.effortTitle, attributes: [.foregroundColor: UIColor.secondaryLabel]))
    }
    title.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .caption1), range: NSRange(location: 0, length: title.length))
    var configuration = UIButton.Configuration.plain()
    configuration.attributedTitle = AttributedString(title)
    configuration.image = UIImage(systemName: "chevron.down")
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 5, weight: .medium)
    configuration.imagePlacement = .trailing
    configuration.imagePadding = 5
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 6)
    configuration.baseForegroundColor = .secondaryLabel
    configuration.titleLineBreakMode = .byTruncatingTail
    modelButton.configuration = configuration
    modelButton.accessibilityLabel = LodyStrings.text("native.chat.composer.modelButton", ["summary": title.string])
    optionsPopover?.render(composerOptions)
    if !modelButton.isEnabled { optionsPopover?.dismiss(animated: true) }
  }
  @objc private func presentComposerOptions() {
    guard modelButton.isEnabled, let controller = presenter(), optionsPopover == nil else { return }
    let panel = ChatComposerModelPanel()
    panel.onModel = { [weak self] in self?.selectModel($0) }
    panel.onEffort = { [weak self] in self?.selectEffort($0) }
    panel.onFast = { [weak self] enabled in
      guard let self else { return }
      self.composerOptions.fast = enabled
      self.updateComposerOptions()
      self.onComposerOptionChange?(["modelId": self.composerOptions.modelId, "effort": self.composerOptions.effort, "fast": enabled])
    }
    panel.loadViewIfNeeded()
    panel.render(composerOptions)
    panel.modalPresentationStyle = .popover
    if let popover = panel.popoverPresentationController {
      popover.sourceView = modelButton
      popover.sourceRect = modelButton.bounds
      popover.permittedArrowDirections = .down
      popover.delegate = panel
    }
    optionsPopover = panel
    controller.present(panel, animated: true)
  }
  private func selectModel(_ id: String) {
    guard composerOptions.modelId != id else { return }
    composerOptions.modelId = id
    composerOptions.effort = ""
    composerOptions.efforts = []
    updateComposerOptions()
    onComposerOptionChange?(["modelId": id, "effort": ""])
  }
  private func selectEffort(_ id: String) {
    guard composerOptions.effort != id else { return }
    composerOptions.effort = id
    updateComposerOptions()
    onComposerOptionChange?(["modelId": composerOptions.modelId, "effort": id])
  }
  func setMentionResult(_ json: String) {
    struct Result: Decodable { let id: String; var path: String?; var item: ChatMentionItem? }
    guard let data = json.data(using: .utf8), let result = try? JSONDecoder().decode(Result.self, from: data), result.id != mentionResultID else { return }
    mentionResultID = result.id
    mentionNeedsFocus = true
    mentionPanel.finishBrowse(path: result.path, selectedItem: result.item)
    focusAfterMentionPicker()
  }
  private func focusAfterMentionPicker() {
    let focus = { [weak self] in
      guard let self, self.window != nil else { return }
      self.mentionNeedsFocus = false
      self.input.becomeFirstResponder()
      self.updateComposer()
    }
    if let transition = presenter()?.transitionCoordinator {
      transition.animate(alongsideTransition: nil) { _ in focus() }
    } else { focus() }
  }
  @objc private func openMentions() { mentionPanel.open(input: input) }
  func textViewDidChangeSelection(_ textView: UITextView) {
    guard activeMentionItems != nil else { return }
    updateComposer()
  }
  func textViewDidChange(_ textView: UITextView) { updateComposer() }
  func textViewDidBeginEditing(_ textView: UITextView) { updateComposer() }
  func textViewDidEndEditing(_ textView: UITextView) { updateComposer(); saveDraft() }
  func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
    (textView.text as NSString).length - range.length + (text as NSString).length <= 32000
  }
  @objc private func submit() {
    guard send.isEnabled else { return }
    if state.running == true && input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty {
      onStop?()
      return
    }
    sendFeedback.impactOccurred(intensity: 0.85)
    let queued = queuesSubmission
    let id = UUID().uuidString.lowercased()
    let body = input.text ?? ""
    if !queued {
      if !body.isEmpty { ChatSendHandoff.begin(id: id, text: body, source: input, background: inputSurface) }
      ChatSendHandoff.beginAttachments(id: id, attachments: attachments, source: attachmentBar)
    }
    takeDraft()
    saveDraft()
    pendingSendID = id
    guard let draft = pendingDraft else { return }
    updateComposer()
    onSend?([
      "id": id,
      "queue": queued,
      "text": draft.text,
      "startedAt": Date().timeIntervalSince1970 * 1000,
      "attachments": draft.attachments.map {
        ["id": $0.id, "name": $0.name, "uri": $0.url.absoluteString, "kind": $0.isImage ? "image" : "file"]
      },
    ])
  }
  @objc private func reconnect() {
    guard let failed = failedDraft else { onReconnect?(); return }
    input.text = [input.text ?? "", failed.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
    for item in failed.attachments where !attachments.contains(where: { $0.id == item.id }) {
      guard let url = URL(string: item.uri), url.isFileURL else { continue }
      attachments.append(ChatAttachment(id: item.id, name: item.name, url: url, isImage: item.kind == "image"))
    }
    restoredSendID = failed.id
    failedDraft = nil
    updateComposer()
    saveDraft()
  }
}
