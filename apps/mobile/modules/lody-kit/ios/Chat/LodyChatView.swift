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
  var onWillDisappear: ((UIViewControllerTransitionCoordinator?) -> Void)?
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
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    let coordinator = transitionCoordinator ?? parent?.transitionCoordinator
    onWillDisappear?(coordinator)
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateTitle?()
  }
}

final class LodyChatView: ExpoView, UICollectionViewDelegateFlowLayout, UIGestureRecognizerDelegate {
  let onSend = EventDispatcher()
  let onStop = EventDispatcher()
  let onSteer = EventDispatcher()
  let onActivityPress = EventDispatcher()
  let onFilePress = EventDispatcher()
  let onTurnChangesPress = EventDispatcher()
  let onReconnect = EventDispatcher()
  let onTitlePress = EventDispatcher()
  let onComposerOptionChange = EventDispatcher()
  private let titleButton = UIButton(type: .system)
  private var navigationTitle = ""
  private var navigationSubtitle = ""
  private var titleDisappearing = false
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
  var lastRenderTime = 0.0
  var renderTailLength = 0
  var rows: [String: ChatRow] = [:]
  var update: DispatchWorkItem?
  var pendingEntries: String?
  var workDurationTimer: Timer?
  let preparation = DispatchQueue(label: "app.innei.lody.chat", qos: .userInitiated)
  var decoding = false
  var displayError: String? { didSet { composer.displayError = displayError } }
  var applying = false
  var needsApply = false
  var followsBottom = true
  var trackingPausedByGesture = false
  var liveEntryID: String?
  let turnFeedback = UINotificationFeedbackGenerator()
  var lastUserID: String?
  var anchoredUserID: String?
  var awaitingUserAnchor = false
  var motionLink: CADisplayLink?
  var motionTime: CFTimeInterval = 0
  var movingLayout = false
  var hasPositionedContent = false
  var rowHeights: [String: (current: CGFloat, target: CGFloat, width: CGFloat)] = [:]
  #if DEBUG
  var scrollProbe: ChatScrollProbe?
  var performanceProbe: ChatPerformanceProbe?
  var streamPerformanceProbe: ChatStreamPerformanceProbe?
  #endif
  private var laidOutHeight: CGFloat = 0
  private var hasInitialDraft = false
  var pendingSend: ChatPendingSend?
  var turnStartedAt: [String: Double] = [:]
  var publishedPendingID: String?
  var handoffID: String?
  var sendScroll: (started: CFTimeInterval, offset: CGFloat)?
  var hasAppeared = false
  var composerHasAcknowledgedSend = false
  private var lastAcknowledgedDraftToken = 0
  private var lastRestoredDraftToken = 0
  private let fileHeaderRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, ChatRow> { cell, _, row in
    var content = UIListContentConfiguration.groupedHeader()
    content.text = row.text
    content.textProperties.font = .preferredFont(forTextStyle: .footnote)
    content.textProperties.color = .secondaryLabel
    content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4)
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
    var content = ChatFileCell.rowContent(for: file.path)
    cell.directionalLayoutMargins.leading = content.directionalLayoutMargins.leading
    cell.directionalLayoutMargins.trailing = content.directionalLayoutMargins.leading
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
      self?.titleDisappearing = false
      self?.deselectFileOnReturn(animated: animated, coordinator: coordinator)
    }
    navigation.onWillDisappear = { [weak self] coordinator in
      self?.titleDisappearing = true
      self?.preserveTitleSubtitle()
      coordinator?.animate(alongsideTransition: nil) { context in
        guard context.isCancelled else { return }
        self?.titleDisappearing = false
        if let owner = self?.scrollOwner {
          ChatNavigationTitle.clearNativeSubtitle(owner.navigationItem)
        }
        self?.attachTitle()
      }
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
      guard let self, !self.applying, !self.movingLayout else { return }
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
        cell.onLink = { [weak self] href in
          if let target = ChatFileLink(href) {
            self?.onFilePress(["path": target.path, "line": target.line ?? 0])
          } else if let url = URL(string: href), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            UIApplication.shared.open(url)
          }
        }
        let width = ChatCell.textWidth(row, width: max(1, collection.bounds.width - 40))
        cell.configure(row, markdown: self.store.view(id: id, text: row.text, secondary: secondary, streaming: row.streaming, width: width))
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
      if payload["queue"] as? Bool != true {
        self.awaitingUserAnchor = true
        self.trackingPausedByGesture = false
        self.followsBottom = true
      }
      self.onSend(payload)
    }
    composer.onStop = { [weak self] in self?.onStop() }
    composer.onSteer = { [weak self] in self?.onSteer(["id": $0]) }
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
    bindScrollOwnerIfNeeded()
    attachTitle()
    updateBottomButton()
    if updateBottomInset(), followsBottom { scrollToBottom() }
    deliverPendingContent()
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
    ChatNavigationTitle.configureButton(titleButton, title: navigationTitle, subtitle: navigationSubtitle)
    attachTitle()
  }

  private func bindScrollOwnerIfNeeded() {
    guard window != nil, scrollOwner == nil else { return }
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

  private func attachTitle() {
    bindScrollOwnerIfNeeded()
    guard window != nil, let owner = scrollOwner else { return }
    guard !navigationTitle.isEmpty || !navigationSubtitle.isEmpty else { return }
    if titleDisappearing {
      ChatNavigationTitle.preserveSubtitle(navigationSubtitle, on: owner.navigationItem)
      return
    }
    ChatNavigationTitle.apply(
      title: navigationTitle,
      subtitle: navigationSubtitle,
      button: titleButton,
      to: owner.navigationItem
    )
  }

  private func preserveTitleSubtitle() {
    guard let owner = scrollOwner else { return }
    ChatNavigationTitle.preserveSubtitle(navigationSubtitle, on: owner.navigationItem)
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
      motionLink?.invalidate(); motionLink = nil
      rowHeights.removeAll()
      #if DEBUG
      scrollProbe?.stop(); scrollProbe = nil
      performanceProbe?.stop(); performanceProbe = nil
      streamPerformanceProbe?.stop(); streamPerformanceProbe = nil
      #endif
      liveEntryID = nil
      update?.cancel(); update = nil
      frameTimer?.invalidate(); frameTimer = nil
      workDurationTimer?.invalidate(); workDurationTimer = nil
      stream.finish()
      if let owner = scrollOwner {
        ChatNavigationTitle.detach(button: titleButton, from: owner.navigationItem)
      }
      if scrollOwner?.contentScrollView(for: .top) === collection {
        scrollOwner?.setContentScrollView(nil, for: .top)
        scrollOwner?.setContentScrollView(nil, for: .bottom)
      }
      scrollOwner = nil
    } else {
      #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--ui-verify-scroll"),
         ProcessInfo.processInfo.arguments.contains("--ui-verify") {
        scrollProbe = ChatScrollProbe(self)
      }
      #endif
      bindScrollOwnerIfNeeded()
      attachTitle()
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
        if pendingSend.rows(entries: transcript.entries).isEmpty && (pendingSend.queue != true || transcript.entries.contains(where: { $0.id == pendingSend.id })) { self.pendingSend = nil }
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
      turnStartedAt[value.id] = nil
      applyRows()
      return
    }
    setPendingSend(value)
  }

  func setPendingSend(_ pending: ChatPendingSend) {
    var value = pending
    var start = turnStartedAt[value.id]
    if start == nil, let supplied = value.startedAt, supplied.isFinite {
      start = supplied
    }
    if start == nil {
      start = Date().timeIntervalSince1970 * 1000
    }
    value.startedAt = start
    turnStartedAt[value.id] = start
    let changed = pendingSend?.id != value.id
    pendingSend = value
    if changed { composerHasAcknowledgedSend = false }
    if changed && value.queue != true {
      handoffID = value.id
      anchoredUserID = value.id + ":user"
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
      turnStartedAt[pendingSend.id] = nil
      self.pendingSend = nil
      applyRows()
    }
    composer.restoreDraft(token: token)
  }
  func setComposerState(_ json: String) { composer.setComposerState(json) }
  func setComposerOptions(_ json: String) { composer.setComposerOptions(json) }
  func setEmptyText(_ text: String) { empty.text = text }
}
