import ExpoModulesCore
import UIKit

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
  let collection: UICollectionView
  let measuringText = ChatTextView()
  var measurements: [String: (width: CGFloat, text: NSAttributedString, height: CGFloat)] = [:]
  let store = ChatMarkdownStore(traits: .current)
  let composer = ChatComposerView(frame: .zero)
  let bottomButton = UIButton(type: .system)
  var imageWorkspace = ""
  var imageSession = ""
  let empty = UILabel()
  private weak var scrollOwner: UIViewController?
  var dataSource: UICollectionViewDiffableDataSource<String, String>!
  var transcript = ChatTranscript()
  var processEntryID = ""
  var processStartID = ""
  var stream = ChatStream()
  var frameTimer: Timer?
  var rendering = false
  var framePending = false
  var rows: [String: ChatRow] = [:]
  var update: DispatchWorkItem?
  var pendingEntries: String?
  let preparation = DispatchQueue(label: "app.innei.lody.chat", qos: .userInitiated)
  var decoding = false
  var displayError: String? { didSet { composer.displayError = displayError } }
  var applying = false
  var needsApply = false
  var followsBottom = true
  var trackingPausedByGesture = false
  var liveEntryID: String?
  var lastUserID: String?
  var anchoredUserID: String?
  var awaitingUserAnchor = false
  var pendingAnchorAnimation = false
  var anchorScrollInFlight = false
  private var laidOutHeight: CGFloat = 0
  private var hasInitialDraft = false
  var pendingSend: ChatPendingSend?
  var publishedPendingID: String?
  var handoffID: String?
  var hasAppeared = false
  var composerHasAcknowledgedSend = false
  private var lastAcknowledgedDraftToken = 0
  private var lastRestoredDraftToken = 0
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
      cell.accessibilityLabel = LodyStrings.text(
        "native.chat.file.diffStats",
        ["text": row.text, "add": file.add ?? 0, "del": file.del ?? 0]
      )
    }
    cell.isAccessibilityElement = true
    cell.accessibilityIdentifier = row.id
    cell.accessibilityTraits = .header
  }
  private let fileRegistration = UICollectionView.CellRegistration<ChatFileCell, ChatRow> { cell, _, row in
    guard let file = row.fileDiff else { return }
    let path = file.path.replacingOccurrences(of: "\\", with: "/") as NSString
    var content = ChatFileCell.rowContent()
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
    cell.accessibilityLabel = LodyStrings.text(
      "native.chat.file.diffStats",
      ["text": file.path, "add": file.add ?? 0, "del": file.del ?? 0]
    )
    cell.accessibilityHint = LodyStrings.text("native.chat.row.openChanges")
  }

  required init(appContext: AppContext? = nil) {
    let layout = UICollectionViewFlowLayout()
    layout.minimumLineSpacing = 0
    layout.minimumInteritemSpacing = 0
    layout.sectionInset = UIEdgeInsets(top: 4, left: 20, bottom: 4, right: 20)
    let collection = ChatCollectionView(frame: .zero, collectionViewLayout: layout)
    self.collection = collection
    super.init(appContext: appContext)
    titleButton.accessibilityIdentifier = "chat-navigation-title"
    titleButton.accessibilityHint = LodyStrings.text("native.chat.title.hint")
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
      if let data = try? JSONSerialization.data(withJSONObject: payload.merging(["status": LodyStrings.text("native.chat.status.sending")]) { _, new in new }),
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
    empty.text = LodyStrings.text("native.chat.empty.loading")
    collection.backgroundView = empty
    addSubview(collection)
    addSubview(composer)
    bottomButton.setImage(UIImage(systemName: "arrow.down"), for: .normal)
    bottomButton.accessibilityLabel = LodyStrings.text("native.chat.scrollToBottom")
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

  func setPendingSend(_ value: ChatPendingSend) {
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
