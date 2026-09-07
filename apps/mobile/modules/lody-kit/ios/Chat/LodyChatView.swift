import ExpoModulesCore
import MarkdownView
import UIKit

final class ChatCell: UICollectionViewCell, UIContextMenuInteractionDelegate {
  var messageContent = ChatMessageContent(frame: .zero)
  var label: ChatTextView { messageContent.label }
  var bubble: UIView { messageContent.bubble }
  let icon = UIImageView()
  let spinner = UIActivityIndicatorView(style: .medium)
  var row: ChatRow?
  var onInteraction: (() -> Void)?
  override init(frame: CGRect) {
    super.init(frame: frame)
    bubble.backgroundColor = .lodyUserBubble
    bubble.layer.cornerRadius = 19
    bubble.layer.cornerCurve = .continuous
    contentView.addSubview(messageContent)
    contentView.addSubview(icon)
    contentView.addSubview(spinner)
    icon.contentMode = .center
    isAccessibilityElement = true
    contentView.addInteraction(UIContextMenuInteraction(delegate: self))
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func configure(_ row: ChatRow, text: NSAttributedString) {
    label.setText(text, animate: row.streaming, reset: self.row?.id != row.id)
    self.row = row
    if row.kind == "user" { ChatSendHandoff.hold(id: row.entryID, target: messageContent) }
    else { messageContent.isHidden = false }
    bubble.isHidden = row.kind != "user"
    icon.image = row.symbol.isEmpty ? nil : UIImage(systemName: row.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13))
    icon.tintColor = chromeColor(for: row)
    row.running && row.kind != "summary" ? spinner.startAnimating() : spinner.stopAnimating()
    accessibilityIdentifier = row.id
    accessibilityLabel = text.string
    accessibilityTraits = row.actionable ? .button : .staticText
    accessibilityHint = hint(for: row)
    label.setShine(row.kind == "summary" && row.running && !row.attention)
    setNeedsLayout()
  }
  func adopt(_ content: ChatMessageContent) {
    let frame = messageContent.frame
    messageContent.removeFromSuperview()
    messageContent = content
    contentView.insertSubview(content, at: 0)
    content.frame = frame
    content.isHidden = false
    content.isUserInteractionEnabled = true
    content.accessibilityElementsHidden = false
    setNeedsLayout()
  }
  override func prepareForReuse() {
    super.prepareForReuse()
    label.setShine(false)
  }
  func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
    guard let row, row.kind == "user", messageContent.frame.contains(location) else { return nil }
    onInteraction?()
    return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
      UIMenu(children: [UIAction(title: "复制", image: UIImage(systemName: "doc.on.doc")) { _ in
        UIPasteboard.general.string = row.text
      }])
    }
  }

  func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                             previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
    contextPreview()
  }

  func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                             previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
    contextPreview()
  }

  private func contextPreview() -> UITargetedPreview? {
    let parameters = UIPreviewParameters()
    parameters.backgroundColor = .lodyUserBubble
    let rect = messageContent.frame
    guard let preview = contentView.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) else { return nil }
    parameters.visiblePath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: rect.size), cornerRadius: 19)
    return UITargetedPreview(view: preview, parameters: parameters,
      target: UIPreviewTarget(container: contentView, center: CGPoint(x: rect.midX, y: rect.midY)))
  }

  static func leading(_ row: ChatRow) -> CGFloat {
    row.kind == "text" || row.kind == "user" ? 0 : 24
  }
  static func textWidth(_ row: ChatRow, width: CGFloat) -> CGFloat {
    // Reserve the status slot even after completion: status cannot rewrap text.
    let reserved: CGFloat = row.kind == "text" || row.kind == "thought" || row.kind == "summary" ? 0 : 28
    if row.kind == "user" { return max(1, width * 0.84 - 26) }
    return max(1, width - leading(row) - reserved)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let row else { return }
    let width = contentView.bounds.width
    if row.kind == "user" {
      let size = label.sizeThatFits(CGSize(width: width * 0.84 - 26, height: .greatestFiniteMagnitude))
      messageContent.frame = CGRect(x: width - size.width - 26, y: 12, width: size.width + 26, height: size.height + 20)
      messageContent.layoutIfNeeded()
    } else {
      messageContent.frame = contentView.bounds
      messageContent.layoutIfNeeded()
      let inset = Self.leading(row)
      let textWidth = Self.textWidth(row, width: width)
      let height = label.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
      let y = row.kind == "text" || row.kind == "thought" ? 6 : max(6, (bounds.height - height) / 2)
      label.frame = CGRect(x: inset, y: y, width: textWidth, height: height)
      icon.frame = CGRect(x: 0, y: y, width: 16, height: min(height, 20))
    }
    spinner.frame = CGRect(x: width - 24, y: (bounds.height - 20) / 2, width: 20, height: 20)
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
    bubble.backgroundColor = .lodyUserBubble
  }
}

final class ChatFileCell: UICollectionViewListCell {
  private let chrome = UIView()
  private let separator = UIView()

  override init(frame: CGRect) {
    super.init(frame: frame)
    automaticallyUpdatesBackgroundConfiguration = false
    backgroundConfiguration = .clear()
    chrome.isUserInteractionEnabled = false
    chrome.layer.cornerCurve = .continuous
    chrome.layer.masksToBounds = true
    insertSubview(chrome, belowSubview: contentView)
    separator.backgroundColor = .separator
    contentView.addSubview(separator)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(group: String, selected: Bool) {
    backgroundConfiguration = .clear()
    chrome.backgroundColor = selected ? .lodyFileGroupSelected : .lodyFileGroup
    chrome.layer.cornerRadius = group == "middle" ? 0 : 12
    switch group {
    case "first":
      chrome.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    case "last":
      chrome.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    case "middle":
      chrome.layer.maskedCorners = []
    default:
      chrome.layer.maskedCorners = [
        .layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
      ]
    }
    separator.isHidden = group == "last" || group == "only" || group.isEmpty
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    chrome.frame = bounds
    let scale = max(traitCollection.displayScale, 1)
    let inset = directionalLayoutMargins.leading + 36
    separator.frame = CGRect(
      x: inset,
      y: bounds.height - 1 / scale,
      width: max(0, bounds.width - inset - 16),
      height: 1 / scale
    )
  }
}

private final class ChatCollectionView: UICollectionView {
  var contentDidLayout: (() -> Void)?
  private var lastSize = CGSize.zero
  override func layoutSubviews() {
    super.layoutSubviews()
    guard contentSize != lastSize else { return }
    lastSize = contentSize
    contentDidLayout?()
  }
}

private final class ChatNavigationController: UIViewController {
  var updateTitle: (() -> Void)?
  var onWillAppear: ((Bool, UIViewControllerTransitionCoordinator?) -> Void)?
  var onDidAppear: (() -> Void)?
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    onDidAppear?()
  }
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    updateTitle?()
    onWillAppear?(animated, transitionCoordinator ?? parent?.transitionCoordinator)
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateTitle?()
  }
}

final class LodyChatView: ExpoView, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
  let onSend = EventDispatcher()
  let onActivityPress = EventDispatcher()
  let onTurnChangesPress = EventDispatcher()
  let onReconnect = EventDispatcher()
  let onTitlePress = EventDispatcher()
  let onComposerOptionChange = EventDispatcher()
  private let titleButton = UIButton(type: .system)
  private var navigationTitle = ""
  private var navigationSubtitle = ""
  private let navigation = ChatNavigationController()
  private let collection: ChatCollectionView
  private let measuringText = ChatTextView()
  private var measurements: [String: (width: CGFloat, text: NSAttributedString, height: CGFloat)] = [:]
  private let store = ChatMarkdownStore(traits: .current)
  private let composer = ChatComposerView(frame: .zero)
  private let bottomButton = UIButton(type: .system)
  private var imageWorkspace = ""
  private var imageSession = ""
  private let empty = UILabel()
  private weak var scrollOwner: UIViewController?
  private var dataSource: UICollectionViewDiffableDataSource<String, String>!
  private var transcript = ChatTranscript()
  private var processEntryID = ""
  private var processStartID = ""
  private var stream = ChatStream()
  private var frameTimer: Timer?
  private var rendering = false
  private var framePending = false
  private var rows: [String: ChatRow] = [:]
  private var update: DispatchWorkItem?
  private var pendingEntries: String?
  private let preparation = DispatchQueue(label: "app.innei.lody.chat", qos: .userInitiated)
  private var decoding = false
  private var displayError: String? { didSet { composer.displayError = displayError } }
  private var applying = false
  private var needsApply = false
  private var followsBottom = true
  private var trackingPausedByGesture = false
  private var liveEntryID: String?
  private var lastUserID: String?
  private var anchoredUserID: String?
  private var awaitingUserAnchor = false
  private var pendingAnchorAnimation = false
  private var anchorScrollInFlight = false
  private var laidOutHeight: CGFloat = 0
  private var hasInitialDraft = false
  private var pendingSend: ChatPendingSend?
  private var publishedPendingID: String?
  private var handoffID: String?
  private var hasAppeared = false

  private let fileHeaderRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ChatRow> { cell, _, row in
    var content = UIListContentConfiguration.groupedHeader()
    content.text = row.text
    content.textProperties.font = .preferredFont(forTextStyle: .footnote)
    content.textProperties.color = .secondaryLabel
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 4, bottom: 6, trailing: 4)
    cell.contentConfiguration = content
    cell.backgroundConfiguration = .clear()
    if let file = row.fileDiff {
      let counts = UILabel()
      counts.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular)
      let value = NSMutableAttributedString(string: "+\(file.add ?? 0)", attributes: [.foregroundColor: UIColor.systemBlue])
      value.append(NSAttributedString(string: "  −\(file.del ?? 0)", attributes: [.foregroundColor: UIColor.systemRed]))
      counts.attributedText = value
      cell.accessories = [.customView(configuration: .init(customView: counts, placement: .trailing()))]
      cell.accessibilityLabel = "\(row.text)，新增 \(file.add ?? 0) 行，删除 \(file.del ?? 0) 行"
    }
    cell.isAccessibilityElement = true
    cell.accessibilityIdentifier = row.id
    cell.accessibilityTraits = .header
  }

  private let fileRegistration = UICollectionView.CellRegistration<ChatFileCell, ChatRow> { cell, _, row in
    guard let file = row.fileDiff else { return }
    let path = file.path.replacingOccurrences(of: "\\", with: "/") as NSString
    var content = chatFileRowContent()
    cell.directionalLayoutMargins.leading = content.directionalLayoutMargins.leading
    cell.directionalLayoutMargins.trailing = content.directionalLayoutMargins.leading
    content.text = path.lastPathComponent
    content.secondaryText = path.deletingLastPathComponent
    cell.contentConfiguration = content
    let counts = UILabel()
    counts.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .regular)
    let value = NSMutableAttributedString(string: "+\(file.add ?? 0)", attributes: [.foregroundColor: UIColor.systemBlue])
    value.append(NSAttributedString(string: "  −\(file.del ?? 0)", attributes: [.foregroundColor: UIColor.systemRed]))
    counts.attributedText = value
    cell.accessories = [.customView(configuration: .init(customView: counts, placement: .trailing())), .disclosureIndicator()]
    cell.configurationUpdateHandler = { cell, state in
      (cell as? ChatFileCell)?.apply(group: row.group, selected: state.isHighlighted || state.isSelected)
      cell.accessibilityTraits = state.isSelected ? [.button, .selected] : .button
    }
    cell.isAccessibilityElement = true
    cell.accessibilityIdentifier = row.id
    cell.accessibilityLabel = "\(file.path)，新增 \(file.add ?? 0) 行，删除 \(file.del ?? 0) 行"
    cell.accessibilityHint = "打开文件改动"
  }

  required init(appContext: AppContext? = nil) {
    let layout = UICollectionViewFlowLayout()
    layout.minimumLineSpacing = 0
    layout.minimumInteritemSpacing = 0
    layout.sectionInset = UIEdgeInsets(top: 4, left: 20, bottom: 4, right: 20)
    collection = ChatCollectionView(frame: .zero, collectionViewLayout: layout)
    super.init(appContext: appContext)
    titleButton.accessibilityIdentifier = "chat-navigation-title"
    titleButton.accessibilityHint = "查看会话详情"
    titleButton.addAction(UIAction { [weak self] _ in self?.onTitlePress() }, for: .touchUpInside)
    navigation.view = UIView(frame: .zero)
    navigation.view.isUserInteractionEnabled = false
    navigation.updateTitle = { [weak self] in self?.attachTitle() }
    navigation.onDidAppear = { [weak self] in
      self?.hasAppeared = true
      self?.deliverPendingContent()
    }
    navigation.onWillAppear = { [weak self] animated, coordinator in
      self?.deselectFileOnReturn(animated: animated, coordinator: coordinator)
    }
    backgroundColor = .systemBackground
    collection.backgroundColor = .clear
    collection.alwaysBounceVertical = true
    collection.keyboardDismissMode = .interactive
    let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
    tap.cancelsTouchesInView = false
    tap.delegate = self
    collection.addGestureRecognizer(tap)
    collection.contentInsetAdjustmentBehavior = .automatic
    collection.delegate = self
    collection.contentDidLayout = { [weak self] in
      guard let self, !self.applying else { return }
      self.updateBottomInset()
      if self.followsBottom { self.scrollToBottom() }
    }
    collection.register(ChatImageCell.self, forCellWithReuseIdentifier: "image")
    collection.register(ChatCell.self, forCellWithReuseIdentifier: "message")
    collection.register(ChatMarkdownCell.self, forCellWithReuseIdentifier: "markdown")
    dataSource = UICollectionViewDiffableDataSource<String, String>(collectionView: collection) { [weak self] collection, index, id in
      guard let self, let row = self.rows[id] else { return nil }
      if row.kind == "changesHeader" {
        return collection.dequeueConfiguredReusableCell(using: self.fileHeaderRegistration, for: index, item: row)
      }
      if row.kind == "changes" {
        return collection.dequeueConfiguredReusableCell(using: self.fileRegistration, for: index, item: row)
      }
      if row.image != nil {
        let cell = collection.dequeueReusableCell(withReuseIdentifier: "image", for: index) as! ChatImageCell
        cell.configure(row, workspace: self.imageWorkspace, session: self.imageSession)
        return cell
      }
      if row.kind == "text" || row.kind == "thought" {
        let cell = collection.dequeueReusableCell(withReuseIdentifier: "markdown", for: index) as! ChatMarkdownCell
        let secondary = row.kind == "thought"
        cell.onLink = { url in
          guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
          UIApplication.shared.open(url)
        }
        cell.configure(row, content: self.store.content(id: id, text: row.text, secondary: secondary), theme: self.store.theme(secondary: secondary))
        return cell
      }
      let cell = collection.dequeueReusableCell(withReuseIdentifier: "message", for: index) as! ChatCell
      cell.onInteraction = { [weak self] in self?.pauseTracking() }
      cell.configure(row, text: self.text(for: row))
      return cell
    }
    if #available(iOS 26.0, *) {
      collection.topEdgeEffect.style = .soft
      collection.bottomEdgeEffect.style = .soft
    }
    composer.attachScrollEdge(to: collection)
    composer.onSend = { [weak self] payload in
      guard let self else { return }
      if let data = try? JSONSerialization.data(withJSONObject: payload.merging(["status": "正在发送…"]) { _, new in new }),
         let pending = try? JSONDecoder().decode(ChatPendingSend.self, from: data) {
        self.setPendingSend(pending)
      }
      self.awaitingUserAnchor = true
      self.trackingPausedByGesture = false
      self.followsBottom = true
      self.onSend(payload)
    }
    composer.onReconnect = { [weak self] in self?.onReconnect([:]) }
    composer.onComposerOptionChange = { [weak self] in self?.onComposerOptionChange($0) }
    empty.numberOfLines = 0
    empty.textAlignment = .center
    empty.font = .dynamic(of: 16)
    empty.textColor = .secondaryLabel
    empty.text = "正在取回对话…"
    collection.backgroundView = empty
    addSubview(collection)
    addSubview(composer)
    bottomButton.setImage(UIImage(systemName: "arrow.down"), for: .normal)
    bottomButton.accessibilityLabel = "回到底部"
    bottomButton.accessibilityIdentifier = "chat-scroll-to-bottom"
    if #available(iOS 26.0, *) { bottomButton.configuration = .glass() }
    else { bottomButton.configuration = .gray() }
    bottomButton.configuration?.cornerStyle = .capsule
    bottomButton.alpha = 0
    bottomButton.isUserInteractionEnabled = false
    bottomButton.addAction(UIAction { [weak self] _ in
      guard let self else { return }
      self.collection.setContentOffset(self.collection.contentOffset, animated: false)
      self.trackingPausedByGesture = false
      self.followsBottom = true
      self.pendingAnchorAnimation = true
      self.scrollToBottom()
    }, for: .touchUpInside)
    addSubview(bottomButton)
    bottomButton.translatesAutoresizingMaskIntoConstraints = false
    collection.translatesAutoresizingMaskIntoConstraints = false
    composer.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      bottomButton.centerXAnchor.constraint(equalTo: composer.centerXAnchor),
      bottomButton.bottomAnchor.constraint(equalTo: composer.topAnchor, constant: -8),
      bottomButton.widthAnchor.constraint(equalToConstant: 44), bottomButton.heightAnchor.constraint(equalToConstant: 44),
      collection.topAnchor.constraint(equalTo: topAnchor),
      collection.leadingAnchor.constraint(equalTo: leadingAnchor), collection.trailingAnchor.constraint(equalTo: trailingAnchor),
      collection.bottomAnchor.constraint(equalTo: bottomAnchor),
      composer.leadingAnchor.constraint(equalTo: leadingAnchor), composer.trailingAnchor.constraint(equalTo: trailingAnchor),
      composer.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
    ])
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if window != nil && scrollOwner == nil {
      var responder = next
      while let current = responder {
        if let controller = current as? UIViewController {
          controller.setContentScrollView(collection, for: .top)
          controller.setContentScrollView(collection, for: .bottom)
          scrollOwner = controller
          if navigation.parent == nil {
            controller.addChild(navigation)
            addSubview(navigation.view)
            navigation.didMove(toParent: controller)
          }
          break
        }
        responder = current.next
      }
    }
    attachTitle()
    updateBottomButton()
    deliverPendingContent()
    if updateBottomInset(), followsBottom { scrollToBottom() }
    if abs(laidOutHeight - collection.bounds.height) > 0.5 {
      laidOutHeight = collection.bounds.height
      if followsBottom { scrollToBottom() }
    }
  }

  func setNavigationTitle(_ title: String) {
    guard navigationTitle != title else { return }
    navigationTitle = title
    updateTitleButton()
  }

  func setNavigationSubtitle(_ subtitle: String) {
    guard navigationSubtitle != subtitle else { return }
    navigationSubtitle = subtitle
    updateTitleButton()
  }

  private func updateTitleButton() {
    var configuration = UIButton.Configuration.plain()
    configuration.title = navigationTitle
    configuration.subtitle = navigationSubtitle.isEmpty ? nil : navigationSubtitle
    configuration.titleAlignment = .leading
    configuration.titleLineBreakMode = .byTruncatingTail
    configuration.subtitleLineBreakMode = .byTruncatingMiddle
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0)
    configuration.baseForegroundColor = .label
    configuration.titleTextAttributesTransformer = .init { attributes in
      var attributes = attributes
      attributes.font = .preferredFont(forTextStyle: .headline)
      return attributes
    }
    configuration.subtitleTextAttributesTransformer = .init { attributes in
      var attributes = attributes
      attributes.font = .preferredFont(forTextStyle: .caption1)
      attributes.foregroundColor = .secondaryLabel
      return attributes
    }
    titleButton.configuration = configuration
    titleButton.accessibilityLabel = [navigationTitle, navigationSubtitle]
      .filter { !$0.isEmpty }.joined(separator: ", ")
    titleButton.sizeToFit()
    titleButton.bounds.size.height = 44
    setNeedsLayout()
  }

  private func attachTitle() {
    guard window != nil, let owner = scrollOwner, !navigationTitle.isEmpty else { return }
    // Own the UIKit title view directly; no RN header subview wrapper.
    if owner.navigationItem.titleView !== titleButton {
      owner.navigationItem.titleView = titleButton
      owner.navigationItem.style = .browser
    }
  }

  override func willMove(toSuperview newSuperview: UIView?) {
    if newSuperview == nil, navigation.parent != nil {
      navigation.willMove(toParent: nil)
      navigation.view.removeFromSuperview()
      navigation.removeFromParent()
    }
    super.willMove(toSuperview: newSuperview)
  }

  private var composerInset: CGFloat {
    processEntryID.isEmpty ? max(0, bounds.maxY - composer.frame.minY - collection.safeAreaInsets.bottom) + 8 : 0
  }

  @discardableResult
  private func updateBottomInset() -> Bool {
    let base = composerInset
    var space: CGFloat = 0
    if let id = anchoredUserID, let index = dataSource.indexPath(for: id),
       let frame = collection.layoutAttributesForItem(at: index)?.frame {
      let naturalBottom = collection.contentSize.height - collection.bounds.height + collection.safeAreaInsets.bottom + base
      space = max(0, frame.minY - collection.adjustedContentInset.top - naturalBottom)
    }
    let bottom = base + space
    guard abs(collection.contentInset.bottom - bottom) > 0.5 else { return false }
    collection.contentInset.bottom = bottom
    collection.verticalScrollIndicatorInsets.bottom = base
    return true
  }

  override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    guard previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory else { return }
    applyDynamicType()
  }

  private func applyDynamicType() {
    store.apply(traits: traitCollection)
    measurements.removeAll()
    empty.font = .dynamic(of: 16, compatibleWith: traitCollection)
    guard dataSource != nil else { return }
    var snapshot = dataSource.snapshot()
    let ids = snapshot.itemIdentifiers
    if !ids.isEmpty {
      snapshot.reconfigureItems(ids)
      dataSource.apply(snapshot, animatingDifferences: false)
    }
    collection.collectionViewLayout.invalidateLayout()
    setNeedsLayout()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      if let handoffID { ChatSendHandoff.cancel(id: handoffID) }
      anchorScrollInFlight = false
      liveEntryID = nil
      update?.cancel(); update = nil
      frameTimer?.invalidate(); frameTimer = nil
      stream.finish()
      if scrollOwner?.navigationItem.titleView === titleButton {
        scrollOwner?.navigationItem.titleView = nil
        scrollOwner?.navigationItem.style = .navigator
      }
      if scrollOwner?.contentScrollView(for: .top) === collection {
        scrollOwner?.setContentScrollView(nil, for: .top)
        scrollOwner?.setContentScrollView(nil, for: .bottom)
      }
      scrollOwner = nil
    } else {
      if pendingEntries != nil { scheduleUpdate() }
      renderFrame()
    }
  }

  func setProcessStartID(_ id: String) {
    guard processStartID != id else { return }
    processStartID = id
    applyRows()
  }

  func setProcessEntryID(_ id: String) {
    guard processEntryID != id else { return }
    processEntryID = id
    composer.isHidden = !id.isEmpty
    setNeedsLayout()
    applyRows()
  }

  func setEntries(_ json: String) {
    pendingEntries = json
    scheduleUpdate()
  }
  private func scheduleUpdate() {
    guard update == nil, !decoding else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      self.update = nil
      guard let json = self.pendingEntries else { return }
      self.pendingEntries = nil
      self.decoding = true
      self.preparation.async { [weak self] in
        let decoded = Result { () -> [ChatEntry] in
          let entries = try JSONDecoder().decode([ChatEntry].self, from: Data(json.utf8))
          guard Set(entries.map(\.id)).count == entries.count,
                entries.allSatisfy({ Set($0.items.map(\.itemId)).count == $0.items.count }) else {
            throw NSError(domain: "LodyChat", code: 1)
          }
          return entries
        }
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.decoding = false
          switch decoded {
          case .success(let entries):
            self.displayError = nil
            let userID = entries.last { $0.role == "user" }?.id
            if self.processEntryID.isEmpty, let userID, userID != self.lastUserID,
               self.lastUserID != nil || self.awaitingUserAnchor {
              self.liveEntryID = nil
              self.anchoredUserID = userID + ":user"
              self.pendingAnchorAnimation = true
              self.anchorScrollInFlight = false
              self.awaitingUserAnchor = false
              self.trackingPausedByGesture = false
              self.followsBottom = true
            }
            self.lastUserID = userID
            self.stream.receive(entries, animate: self.window != nil && !UIAccessibility.isReduceMotionEnabled)
            self.renderFrame()
            self.startFrameTimer()
          case .failure:
            self.displayError = "对话暂时无法显示 · 点此重新同步"
          }
          if self.pendingEntries != nil { self.scheduleUpdate() }
        }
      }
    }
    update = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
  }

  private func startFrameTimer() {
    guard frameTimer == nil, stream.hasPending, window != nil else { return }
    let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] timer in
      guard let self, self.window != nil else { timer.invalidate(); return }
      if UIAccessibility.isReduceMotionEnabled { self.stream.finish() }
      self.renderFrame()
      if !self.stream.hasPending { timer.invalidate(); self.frameTimer = nil }
    }
    frameTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  private func renderFrame() {
    guard !rendering else { framePending = true; return }
    rendering = true
    stream.advance()
    let entries = stream.presentation
    let parser = store.parser
    preparation.async { [weak self] in
      for entry in entries.suffix(2) {
        for item in entry.items where item.type == "text" || item.type == "thought" {
          _ = parser.parse(item.text ?? "")
        }
      }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.transcript.entries = entries
        self.applyRows()
        self.rendering = false
        if self.framePending { self.framePending = false; self.renderFrame() }
      }
    }
  }

  private func text(for row: ChatRow) -> NSAttributedString {
    let scale = UIFont.dynamicScale(compatibleWith: traitCollection)
    let paragraph = NSMutableParagraphStyle()
    let lineHeight = (row.kind == "user" ? 25 : 18) * scale
    paragraph.minimumLineHeight = lineHeight
    paragraph.maximumLineHeight = lineHeight
    let font = UIFont.dynamic(of: row.kind == "user" ? 17 : 13, compatibleWith: traitCollection)
    return NSAttributedString(string: row.text, attributes: [
      .font: font,
      .foregroundColor: textColor(for: row),
      .paragraphStyle: paragraph,
      .baselineOffset: (lineHeight - font.lineHeight) / 2,
    ])
  }

  private func applyRows() {
    guard !applying else { needsApply = true; return }
    applying = true
    let previousOffset = collection.contentOffset.y
    if composerHasAcknowledgedSend, let pendingSend, pendingSend.rows(entries: transcript.entries).isEmpty {
      self.pendingSend = nil
    }
    var projected = transcript.rows(processEntryID: processEntryID, processStartID: processStartID)
    if processEntryID.isEmpty, let pendingSend { projected += pendingSend.rows(entries: transcript.entries) }
    let liveEntryID = transcript.entries.last { $0.isRunning && (processEntryID.isEmpty || $0.id == processEntryID) }?.id
    let starting = self.liveEntryID == nil && liveEntryID != nil
    let nearTail = collection.contentSize.height - collection.bounds.height + collection.adjustedContentInset.bottom - previousOffset < CGFloat(ChatScroll.resumeDistance)
    let following = followsBottom || (starting && nearTail && !trackingPausedByGesture)
    followsBottom = following
    let completing = self.liveEntryID != nil && liveEntryID == nil
    let anchorID = completing && following
      ? projected.last(where: { $0.entryID == self.liveEntryID && $0.kind == "text" })?.id
      : collection.indexPathsForVisibleItems.sorted().compactMap { dataSource.itemIdentifier(for: $0) }.first(where: { id in projected.contains { $0.id == id } })
    let anchor = anchorID.flatMap { id -> (String, CGFloat)? in
      guard let index = dataSource.indexPath(for: id), let frame = collection.layoutAttributesForItem(at: index)?.frame else { return nil }
      return (id, frame.minY - previousOffset)
    }
    guard Set(projected.map(\.id)).count == projected.count else {
      applying = false
      displayError = "对话暂时无法显示 · 点此重新同步"
      return
    }
    self.liveEntryID = liveEntryID
    let folding = completing && processEntryID.isEmpty && window != nil
    let previous = rows
    rows = Dictionary(projected.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    measurements = measurements.filter { rows[$0.key] != nil }
    store.retain(Set(rows.keys))
    var snapshot = NSDiffableDataSourceSnapshot<String, String>()
    let grouped = Dictionary(grouping: projected, by: \.entryID)
    var entryIDs = transcript.entries.map(\.id)
    if let pendingSend, !entryIDs.contains(pendingSend.id) { entryIDs.append(pendingSend.id) }
    for id in entryIDs {
      guard let entryRows = grouped[id], !entryRows.isEmpty else { continue }
      snapshot.appendSections([id])
      snapshot.appendItems(entryRows.map(\.id), toSection: id)
    }
    snapshot.reconfigureItems(projected.filter { previous[$0.id] != nil && previous[$0.id] != $0 }.map(\.id))
    empty.isHidden = !projected.isEmpty
    let updateLayout = { [self] in
      self.collection.collectionViewLayout.invalidateLayout()
      self.collection.layoutIfNeeded()
      self.updateBottomInset()
      if following { self.scrollToBottom() }
      else if let (id, offset) = anchor, let index = self.dataSource.indexPath(for: id), let frame = self.collection.layoutAttributesForItem(at: index)?.frame {
        self.collection.contentOffset.y = max(-self.collection.adjustedContentInset.top, frame.minY - offset)
      }
      self.updateBottomButton()
      self.deliverPendingContent()
    }
    let finish = { [weak self] in
      guard let self else { return }
      self.applying = false
      if self.needsApply { self.needsApply = false; self.applyRows() }
    }
    if folding && !UIAccessibility.isReduceMotionEnabled {
      UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut]) {
        self.dataSource.apply(snapshot, animatingDifferences: true, completion: finish)
        updateLayout()
      }
    } else if folding {
      UIView.transition(with: collection, duration: 0.12, options: [.transitionCrossDissolve]) {
        self.dataSource.apply(snapshot, animatingDifferences: false)
        updateLayout()
      } completion: { _ in finish() }
    } else {
      dataSource.apply(snapshot, animatingDifferences: false) {
        updateLayout()
        finish()
      }
    }
  }

  func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
    guard let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id] else { return false }
    return row.kind == "changes" || row.actionable || row.image != nil
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    if let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id], row.kind == "changes", let file = row.fileDiff {
      onTurnChangesPress(["entryId": row.entryID, "path": file.path])
      return
    }
    collectionView.deselectItem(at: indexPath, animated: false)
    if let cell = collectionView.cellForItem(at: indexPath) as? ChatImageCell, let controller = presenter() {
      pauseTracking()
      cell.presentPreview(from: controller)
      return
    }
    guard let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id], row.actionable else { return }
    if let pendingSend, id == pendingSend.id + ":pending", pendingSend.reconnect == true {
      onReconnect([:])
      return
    }
    onActivityPress(["entryId": row.entryID, "itemId": row.itemID, "processStartId": row.processStartID])
  }

  private func deselectFileOnReturn(animated: Bool, coordinator: UIViewControllerTransitionCoordinator?) {
    guard let index = collection.indexPathsForSelectedItems?.first,
      let id = dataSource.itemIdentifier(for: index) else { return }
    guard let coordinator else {
      collection.deselectItem(at: index, animated: animated)
      return
    }
    let started = coordinator.animate(alongsideTransition: { [weak self] _ in
      guard let self, let current = self.dataSource.indexPath(for: id) else { return }
      self.collection.deselectItem(at: current, animated: animated)
    }, completion: { [weak self] context in
      guard context.isCancelled, let self, let current = self.dataSource.indexPath(for: id) else { return }
      self.collection.selectItem(at: current, animated: false, scrollPosition: [])
    })
    if !started { collection.deselectItem(at: index, animated: animated) }
  }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    guard scrollView === collection else { return }
    pauseTracking()
  }
  private func pauseTracking() {
    followsBottom = false
    trackingPausedByGesture = true
    anchorScrollInFlight = false
    pendingAnchorAnimation = false
  }
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrollView === collection else { return }
    updateBottomButton()
  }
  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    guard scrollView === collection, !decelerate else { return }
    resumeTrackingAtBottom()
  }
  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    guard scrollView === collection else { return }
    resumeTrackingAtBottom()
  }
  private func resumeTrackingAtBottom() {
    guard bottomOffset - collection.contentOffset.y <= 1 else { return }
    trackingPausedByGesture = false
    followsBottom = true
    scrollToBottom()
  }
  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
    guard scrollView === collection else { return }
    anchorScrollInFlight = false
    if followsBottom { scrollToBottom() }
  }
  private var bottomOffset: CGFloat {
    CGFloat(ChatScroll.bottom(contentHeight: Double(collection.contentSize.height),
      viewportHeight: Double(collection.bounds.height), topInset: Double(collection.adjustedContentInset.top),
      bottomInset: Double(collection.adjustedContentInset.bottom)))
  }

  private func updateBottomButton() {
    let bottom = bottomOffset
    let visible = processEntryID.isEmpty && bottom - collection.contentOffset.y > CGFloat(ChatScroll.resumeDistance)
    guard visible != bottomButton.isUserInteractionEnabled else { return }
    bottomButton.isUserInteractionEnabled = visible
    bottomButton.accessibilityElementsHidden = !visible
    UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
      self.bottomButton.alpha = visible ? 1 : 0
    }
  }

  private func scrollToBottom() {
    guard !anchorScrollInFlight, !collection.isDragging, !collection.isDecelerating else { return }
    if pendingAnchorAnimation, let id = anchoredUserID, dataSource.indexPath(for: id) == nil { return }
    let bottom = bottomOffset
    let animate = pendingAnchorAnimation && !UIAccessibility.isReduceMotionEnabled && abs(collection.contentOffset.y - bottom) > 1
    pendingAnchorAnimation = false
    anchorScrollInFlight = animate
    if abs(collection.contentOffset.y - bottom) > 0.5 {
      collection.setContentOffset(CGPoint(x: 0, y: bottom), animated: animate)
    }
  }

  private func measure(_ row: ChatRow, width: CGFloat) -> CGFloat {
    if let image = row.image {
      let height = ChatImageCell.size(image, width: width).height
      return height
    }
    let textWidth = ChatCell.textWidth(row, width: width)
    if row.kind == "text" || row.kind == "thought" {
      return store.height(id: row.id, text: row.text, secondary: row.kind == "thought", width: textWidth)
    }
    let text = text(for: row)
    if let cached = measurements[row.id], cached.width == textWidth, cached.text.isEqual(to: text) {
      return cached.height
    }
    measuringText.setText(text)
    let height = measuringText.sizeThatFits(CGSize(width: textWidth, height: .greatestFiniteMagnitude)).height
    measurements[row.id] = (textWidth, text, height)
    return height
  }

  func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    let width = max(1, collectionView.bounds.width - 40)
    guard let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id] else { return CGSize(width: width, height: 0) }
    if row.kind == "changesHeader" {
      return CGSize(width: width, height: 32)
    }
    if row.kind == "changes" {
      return CGSize(width: width, height: chatFileRowHeight())
    }
    let measured = measure(row, width: width)
    return CGSize(width: width, height: max(row.actionable || row.kind == "summary" ? 44 : 0, measured + (row.kind == "user" ? 44 : 12)))
  }

  func setAttachmentContext(_ json: String) {
    guard let data = json.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
    let workspace = value["workspaceId"] ?? "", session = value["sessionId"] ?? ""
    guard workspace != imageWorkspace || session != imageSession else { return }
    imageWorkspace = workspace; imageSession = session
    collection.reloadData()
  }
  private func presenter() -> UIViewController? {
    var responder: UIResponder? = next
    while let current = responder {
      if let controller = current as? UIViewController { return controller.presentedViewController ?? controller }
      responder = current.next
    }
    return window?.rootViewController
  }
  @objc private func dismissKeyboard() { endEditing(true) }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    !(touch.view is UITextView)
  }
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
  func setDraftKey(_ key: String) {
    guard !key.isEmpty else { composer.onDraftChange = nil; return }
    let store = LocalStore.shared
    composer.onDraftChange = { text in
      LocalStore.queue.async { try? store.write(key, text) }
    }
    LocalStore.queue.async { [weak self] in
      guard let text = try? store.read(key), !text.isEmpty else { return }
      DispatchQueue.main.async { self?.composer.setStoredDraft(text) }
    }
  }
  private func deliverPendingContent() {
    guard let id = handoffID, window != nil else { return }
    guard hasAppeared else { return }
    collection.layoutIfNeeded()
    for cell in collection.visibleCells {
      if let image = cell as? ChatImageCell { image.layoutIfNeeded(); image.deliverPendingImage() }
      guard let cell = cell as? ChatCell, cell.row?.entryID == id, cell.row?.kind == "user" else { continue }
      cell.layoutIfNeeded()
      ChatSendHandoff.deliver(id: id, to: cell.messageContent) { [weak cell] content in
        guard let cell, cell.row?.entryID == id else { content.removeFromSuperview(); return }
        cell.adopt(content)
      }
    }
  }

  func setPendingSendJSON(_ json: String) {
    guard !json.isEmpty else {
      // A stale initial empty prop must not erase a send handled in this native frame.
      if let publishedPendingID, let pendingSend, pendingSend.id == publishedPendingID {
        // entriesJSON is decoded off-main. Keep the local rows until the same
        // authoritative rows arrive, even if React retires its pending prop first.
        if pendingSend.rows(entries: transcript.entries).isEmpty { self.pendingSend = nil }
        self.publishedPendingID = nil
        applyRows()
      }
      return
    }
    guard let value = try? JSONDecoder().decode(ChatPendingSend.self, from: Data(json.utf8)), !value.id.isEmpty else { return }
    publishedPendingID = value.id
    composer.setPendingSend(value)
    if value.failed == true {
      ChatSendHandoff.cancel(id: value.id)
      if pendingSend?.id == value.id { pendingSend = nil }
      applyRows()
      return
    }
    setPendingSend(value)
  }

  private var composerHasAcknowledgedSend = false
  private var lastAcknowledgedDraftToken = 0
  private var lastRestoredDraftToken = 0
  private func setPendingSend(_ value: ChatPendingSend) {
    let changed = pendingSend?.id != value.id
    pendingSend = value
    if changed {
      composerHasAcknowledgedSend = false
      handoffID = value.id
      anchoredUserID = value.id + ":user"
      pendingAnchorAnimation = false
      followsBottom = true
      trackingPausedByGesture = false
    }
    applyRows()
  }

  func setInitialDraft(_ text: String) {
    guard !hasInitialDraft else { return }
    hasInitialDraft = true
    composer.setInitialDraft(text)
    awaitingUserAnchor = !text.isEmpty
  }
  func setInitialAttachments(_ json: String) { composer.setInitialAttachments(json) }
  func clearDraft(token: Int) {
    guard token > lastAcknowledgedDraftToken else { return }
    lastAcknowledgedDraftToken = token
    composerHasAcknowledgedSend = true
    composer.clearDraft(token: token)
    applyRows()
  }
  func restoreDraft(token: Int) {
    guard token > lastRestoredDraftToken else { return }
    lastRestoredDraftToken = token
    if let pendingSend {
      ChatSendHandoff.cancel(id: pendingSend.id)
      self.pendingSend = nil
      applyRows()
    }
    composer.restoreDraft(token: token)
  }
  func setComposerState(_ json: String) { composer.setComposerState(json) }
  func setComposerOptions(_ json: String) { composer.setComposerOptions(json) }
  func setEmptyText(_ text: String) { empty.text = text }
}

private func chatFileRowContent() -> UIListContentConfiguration {
  var content = UIListContentConfiguration.subtitleCell()
  content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
  content.textProperties.font = .preferredFont(forTextStyle: .subheadline)
  content.textProperties.numberOfLines = 1
  content.textProperties.lineBreakMode = .byTruncatingMiddle
  content.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
  content.secondaryTextProperties.color = .secondaryLabel
  content.secondaryTextProperties.numberOfLines = 1
  content.secondaryTextProperties.lineBreakMode = .byTruncatingMiddle
  content.image = UIImage(systemName: "doc.text")
  content.imageProperties.tintColor = .secondaryLabel
  content.imageProperties.preferredSymbolConfiguration = .init(textStyle: .body)
  return content
}

private func chatFileRowHeight() -> CGFloat {
  var content = chatFileRowContent()
  content.text = "Filename"
  content.secondaryText = "path"
  let view = UIListContentView(configuration: content)
  let height = view.systemLayoutSizeFitting(
    CGSize(width: 320, height: UIView.layoutFittingCompressedSize.height),
    withHorizontalFittingPriority: .fittingSizeLevel,
    verticalFittingPriority: .fittingSizeLevel
  ).height
  return max(64, ceil(height))
}

private func chromeColor(for row: ChatRow) -> UIColor {
  if row.attention { return .systemOrange }
  if row.kind == "changes" || (row.kind == "summary" && row.running) { return .systemBlue }
  return .secondaryLabel
}

private func textColor(for row: ChatRow) -> UIColor {
  if row.attention { return .systemOrange }
  if row.kind == "changes" || (row.kind == "summary" && row.running) { return .systemBlue }
  if row.kind == "user" { return .label }
  return .secondaryLabel
}

private func hint(for row: ChatRow) -> String? {
  if row.id == row.entryID + ":pending" {
    return row.actionable ? "重新连接并继续发送" : nil
  }
  switch row.kind {
  case "summary": return "打开执行过程"
  case "changes": return "打开文件改动"
  default: return nil
  }
}
