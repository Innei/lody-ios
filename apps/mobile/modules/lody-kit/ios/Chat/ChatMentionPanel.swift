import UIKit

struct ChatMentionItem: Decodable, Equatable {
  let path: String
  let name: String
  let kind: String
  let subtitle: String
  var insertText: String?

  func matches(_ query: String) -> Bool {
    query.isEmpty || (name + " " + path + " " + subtitle).localizedStandardContains(query)
  }

  var content: UIListContentConfiguration {
    var content = UIListContentConfiguration.subtitleCell()
    content.text = name
    content.secondaryText = subtitle
    content.textProperties.font = .dynamic(of: 16, weight: .medium)
    content.secondaryTextProperties.font = .dynamic(of: 13)
    content.secondaryTextProperties.color = .secondaryLabel
    content.secondaryTextProperties.numberOfLines = 1
    let glyphs = ["file": "doc.text", "directory": "folder", "skill": "sparkles", "category": "folder"]
    var glyph = glyphs[kind] ?? "doc.text"
    if kind == "category" && path == "skill" { glyph = "sparkles" }
    content.image = UIImage(systemName: glyph, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))
    content.imageProperties.tintColor = .secondaryLabel
    content.imageProperties.maximumSize = CGSize(width: 20, height: 20)
    content.imageProperties.reservedLayoutSize = CGSize(width: 32, height: 32)
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 9, leading: 14, bottom: 9, trailing: 14)
    return content
  }
}

/// Typing completes in place; explicit category selection delegates to a page sheet.
final class ChatMentionPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
  private let list: UICollectionView
  private let contentBlur = UIVisualEffectView(effect: nil)
  private var motion: UIViewPropertyAnimator?
  private var showing = false
  private var rows: [ChatMentionItem] = []
  private var catalog: [ChatMentionItem] = []
  private var query = ""
  private var applyingEdit = false
  private var range: NSRange?
  private var dismissedText: String?
  private var browserDraft: (text: String, range: NSRange)?
  private weak var input: UITextView?
  var onChange: (() -> Void)?
  var onBrowse: (([String: String]) -> Void)?
  private(set) var panelHeight: CGFloat = 0

  override init(frame: CGRect) {
    var config = UICollectionLayoutListConfiguration(appearance: .plain)
    config.backgroundColor = .clear
    config.showsSeparators = false
    list = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout.list(using: config))
    super.init(frame: frame)
    let surface = UIVisualEffectView()
    if #available(iOS 26.0, *) {
      surface.effect = UIGlassEffect(style: .regular)
      surface.cornerConfiguration = .capsule(maximumRadius: 18)
    } else {
      surface.effect = UIBlurEffect(style: .systemMaterial)
    }
    surface.isUserInteractionEnabled = false
    surface.frame = bounds
    surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(surface)
    layer.cornerRadius = 18
    layer.cornerCurve = .continuous
    clipsToBounds = true
    accessibilityIdentifier = "mention-panel"
    isHidden = true
    list.backgroundColor = .clear
    list.contentInsetAdjustmentBehavior = .never
    list.contentInset = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
    list.keyboardDismissMode = .none
    list.dataSource = self
    list.delegate = self
    list.register(UICollectionViewListCell.self, forCellWithReuseIdentifier: "candidate")
    addSubview(list)
    contentBlur.isUserInteractionEnabled = false
    contentBlur.frame = bounds
    contentBlur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(contentBlur)
    list.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      list.topAnchor.constraint(equalTo: topAnchor), list.bottomAnchor.constraint(equalTo: bottomAnchor),
      list.leadingAnchor.constraint(equalTo: leadingAnchor), list.trailingAnchor.constraint(equalTo: trailingAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window == nil else { return }
    showing = false
    if motion?.state == .active { motion?.stopAnimation(true) }
    motion = nil
    isHidden = true
    panelHeight = 0
    contentBlur.effect = nil
  }

  private func setVisible(_ visible: Bool) {
    guard showing != visible else { return }
    showing = visible
    if motion?.state == .active {
      motion?.stopAnimation(false)
      motion?.finishAnimation(at: .current)
    }
    motion = nil
    isUserInteractionEnabled = visible
    guard window != nil else {
      isHidden = !visible
      alpha = visible ? 1 : 0
      if !visible { panelHeight = 0 }
      return
    }
    let reduced = UIAccessibility.isReduceMotionEnabled
    if visible && isHidden {
      alpha = 0
      transform = CGAffineTransform(translationX: 0, y: reduced ? 0 : 4)
      contentBlur.effect = reduced ? nil : UIBlurEffect(style: .systemUltraThinMaterial)
    }
    isHidden = false
    var duration = visible ? 0.2 : 0.14
    if reduced { duration = 0.12 }
    let animation = UIViewPropertyAnimator(duration: duration, curve: visible ? .easeOut : .easeIn) { [weak self] in
      guard let self else { return }
      self.alpha = visible ? 1 : 0
      self.transform = CGAffineTransform(translationX: 0, y: visible || reduced ? 0 : 4)
      self.contentBlur.effect = visible || reduced ? nil : UIBlurEffect(style: .systemUltraThinMaterial)
    }
    animation.addCompletion { [weak self] position in
      guard let self, position == .end, self.showing == visible else { return }
      self.motion = nil
      self.contentBlur.effect = nil
      if !visible {
        self.isHidden = true
        self.panelHeight = 0
        self.onChange?()
      }
    }
    motion = animation
    DispatchQueue.main.async { [weak self, weak animation] in
      guard let self, let animation, self.motion === animation else { return }
      self.superview?.layoutIfNeeded()
      animation.startAnimation()
    }
  }

  // NSString ranges match UITextView selections, including emoji before the trigger.
  static func activeRange(text: String, selection: NSRange) -> NSRange? {
    let text = text as NSString
    guard selection.length == 0, selection.location > 0, selection.location <= text.length else { return nil }
    let prefix = text.substring(to: selection.location)
    guard let token = prefix.range(of: "(?:^|\\s)@[^\\s@]*$", options: .regularExpression),
          let at = prefix[token].firstIndex(of: "@") else { return nil }
    return NSRange(at..<prefix.endIndex, in: prefix)
  }

  func update(input: UITextView, items: [ChatMentionItem], enabled: Bool = true) {
    guard !applyingEdit else { return }
    self.input = input
    catalog = items
    range = Self.activeRange(text: input.text ?? "", selection: input.selectedRange)
    let correction: UITextAutocorrectionType = range != nil && enabled ? .no : .default
    if input.autocorrectionType != correction {
      input.autocorrectionType = correction
      input.reloadInputViews()
    }
    guard input.isFirstResponder, input.markedTextRange == nil, browserDraft == nil,
          enabled, let range, dismissedText != input.text else {
      setVisible(false)
      return
    }
    query = ((input.text ?? "") as NSString).substring(with: NSRange(location: range.location + 1, length: range.length - 1))
    let nextRows: [ChatMentionItem]
    if query.isEmpty {
      nextRows = [
        ChatMentionItem(path: "file", name: LodyStrings.text("native.chat.mention.files"), kind: "category", subtitle: ""),
        ChatMentionItem(path: "skill", name: LodyStrings.text("native.chat.mention.skills"), kind: "category", subtitle: ""),
      ]
    } else {
      nextRows = items.filter { $0.matches(query) }
    }
    guard !nextRows.isEmpty else {
      setVisible(false)
      return
    }
    panelHeight = min(240, CGFloat(nextRows.count) * (query.isEmpty ? 50 : 58) + 12)
    if rows != nextRows {
      rows = nextRows
      if showing && motion == nil {
        UIView.transition(with: list, duration: 0.09, options: [.transitionCrossDissolve, .beginFromCurrentState, .allowAnimatedContent]) {
          self.list.reloadData()
        }
      } else {
        list.reloadData()
      }
    }
    setVisible(true)
  }

  func open(input: UITextView) {
    dismissedText = nil
    input.becomeFirstResponder()
    if Self.activeRange(text: input.text ?? "", selection: input.selectedRange) == nil {
      let text = (input.text ?? "") as NSString
      let caret = input.selectedRange.location
      var prefix = ""
      if caret > 0 && text.substring(to: caret).last?.isWhitespace == false { prefix = " " }
      input.insertText(prefix + "@")
    }
    onChange?()
  }

  func finishBrowse(path: String?, selectedItem: ChatMentionItem? = nil) {
    guard let input, let draft = browserDraft else { return }
    browserDraft = nil
    guard input.text == draft.text else { return }
    if let path, let item = selectedItem ?? catalog.first(where: { $0.path == path }), item.path == path {
      insert(item, into: input, range: draft.range)
    } else {
      dismissedText = input.text
      onChange?()
    }
  }

  private func insert(_ item: ChatMentionItem, into input: UITextView, range: NSRange) {
    let label = item.kind == "skill" ? item.name : item.path
    let text = (item.insertText ?? ("@" + label)) + " "
    let currentLength = ((input.text ?? "") as NSString).length
    guard NSMaxRange(range) <= currentLength, currentLength - range.length + (text as NSString).length <= 32000 else { return }
    applyingEdit = true
    input.selectedRange = range
    input.insertText(text)
    applyingEdit = false
    input.textStorage.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: NSRange(location: range.location, length: (text as NSString).length - 1))
    input.typingAttributes[.foregroundColor] = UIColor.label
    onChange?()
  }

  func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { rows.count }
  func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let item = rows[indexPath.item]
    let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "candidate", for: indexPath) as! UICollectionViewListCell
    var content = item.content
    if item.kind == "category" {
      content.secondaryText = nil
      content.textProperties.font = .dynamic(of: 15)
      let glyph = item.path == "file" ? "folder" : "sparkles"
      content.image = UIImage(systemName: glyph, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
      content.imageProperties.maximumSize = CGSize(width: 16, height: 16)
      content.imageProperties.reservedLayoutSize = CGSize(width: 20, height: 20)
      content.imageToTextPadding = 12
      content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 15, leading: 16, bottom: 15, trailing: 16)
    } else {
      content.text = "@" + (item.kind == "skill" ? item.name : item.path)
    }
    cell.contentConfiguration = content
    cell.backgroundConfiguration = .clear()
    cell.accessibilityIdentifier = "mention-item:" + item.path
    cell.accessories = []
    if item.kind == "category" {
      let arrow = UIImageView(image: UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .regular)))
      arrow.tintColor = .tertiaryLabel
      arrow.contentMode = .center
      arrow.frame = CGRect(x: 0, y: 0, width: 16, height: 16)
      cell.accessories = [.customView(configuration: .init(customView: arrow, placement: .trailing()))]
    }
    return cell
  }
  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    collectionView.deselectItem(at: indexPath, animated: true)
    guard let input, let range else { return }
    let item = rows[indexPath.item]
    if item.kind == "category" {
      browserDraft = (input.text ?? "", range)
      input.resignFirstResponder()
      onChange?()
      onBrowse?(["category": item.path, "query": query])
    } else {
      insert(item, into: input, range: range)
    }
  }
}

#if DEBUG
/// Exercise the production SessionScreen/CreateSessionScreen wiring without a cloud account.
@MainActor enum MentionFixture {
  static func response(_ payload: String, options: Bool = false) -> String? {
    guard ProcessInfo.processInfo.arguments.contains("--ui-verify"),
          ProcessInfo.processInfo.arguments.contains("--ui-verify-mentions"),
          let data = payload.data(using: .utf8),
          let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          args["workspaceId"] as? String == "ui-home" else { return nil }
    if options {
      return #"{"sessionId":"ui-new","agents":[{"id":"fixture","name":"Fixture Agent","machineId":"ui","machineName":"Fixture Mac","cliType":"builtin","agentType":"codex"}],"capabilities":[]}"#
    }
    if args["category"] as? String == "skill" {
      return #"{"items":[{"path":"/fixture/skills/auth/SKILL.md","name":"auth-review","kind":"skill","subtitle":"Review authentication","insertText":"use /auth-review [Skill Path](</fixture/skills/auth/SKILL.md>)"}],"truncated":false,"incomplete":false}"#
    }
    return #"{"items":[{"path":"src","name":"src","kind":"directory","subtitle":""},{"path":"src/session.ts","name":"session.ts","kind":"file","subtitle":"src","insertText":"@src/session.ts"}],"truncated":false,"incomplete":false}"#
  }
}
#endif
