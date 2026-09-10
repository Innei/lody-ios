import UIKit

extension LodyChatView {
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
    #if DEBUG
    if historyLoadStarted == 0 { historyLoadStarted = CACurrentMediaTime() }
    #endif
    pendingEntries = json
    scheduleUpdate()
  }

  func scheduleUpdate() {
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
            #if DEBUG
            self.streamPerformanceProbe?.receive(entries)
            #endif
            self.displayError = nil
            let userID = entries.last { $0.role == "user" && !$0.isQueued }?.id
            if self.processEntryID.isEmpty, let userID, userID != self.lastUserID,
               self.awaitingUserAnchor {
              self.liveEntryID = nil
              self.anchoredUserID = userID + ":user"
              self.awaitingUserAnchor = false
              self.trackingPausedByGesture = false
              self.followsBottom = true
            }
            self.lastUserID = userID
            self.stream.receive(entries, animate: self.window != nil && !UIAccessibility.isReduceMotionEnabled)
            self.startFrameTimer()
          case .failure:
            self.displayError = LodyStrings.text("native.chat.error.transcript")
          }
          if self.pendingEntries != nil { self.scheduleUpdate() }
        }
      }
    }
    update = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
  }

  func startFrameTimer() {
    guard frameTimer == nil else { return }
    guard !rendering else { framePending = true; return }
    guard window != nil else { stream.finish(); return }
    let interval = ChatStream.commitInterval(tailLength: renderTailLength)
    let delay = max(0.001, lastRenderTime + interval - CACurrentMediaTime())
    let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.frameTimer = nil
        if UIAccessibility.isReduceMotionEnabled { self.stream.finish() }
        self.renderFrame()
      }
    }
    frameTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func renderFrame() {
    guard !rendering else { framePending = true; return }
    rendering = true
    lastRenderTime = CACurrentMediaTime()
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
        if self.framePending || self.stream.hasPending {
          self.framePending = false
          self.startFrameTimer()
        }
      }
    }
  }

  func text(for row: ChatRow) -> NSAttributedString {
    let scale = UIFont.dynamicScale(compatibleWith: traitCollection)
    let paragraph = NSMutableParagraphStyle()
    let lineHeight = (row.kind == "user" ? 25 : 18) * scale
    paragraph.minimumLineHeight = lineHeight
    paragraph.maximumLineHeight = lineHeight
    let font = ChatCell.messageFont(for: row, compatibleWith: traitCollection)
    return NSAttributedString(string: row.text, attributes: [
      .font: font,
      .foregroundColor: textColor(for: row),
      .paragraphStyle: paragraph,
      .baselineOffset: (lineHeight - font.lineHeight) / 2,
    ])
  }

  func applyRows() {
    guard !applying else { needsApply = true; return }
    applying = true
    #if DEBUG
    let commitStart = CACurrentMediaTime()
    #endif
    let previousOffset = collection.contentOffset.y
    if composerHasAcknowledgedSend, let pendingSend,
       transcript.entries.contains(where: { $0.id == pendingSend.id }),
       pendingSend.rows(entries: transcript.entries).isEmpty {
      self.pendingSend = nil
    }
    var queue = transcript.entries.filter(\.isQueued).map { entry in
      ChatQueuedDraft(
        id: entry.id,
        text: entry.items.compactMap { $0.type == "text" ? $0.text : nil }.joined(separator: "\n"),
        canSteer: entry.canSteer != false,
        attachments: entry.items.compactMap { $0.image?.fileName ?? $0.file?.fileName }
      )
    }
    if let pendingSend, pendingSend.queue == true, pendingSend.failed != true,
       !transcript.entries.contains(where: { $0.id == pendingSend.id }) {
      queue.append(ChatQueuedDraft(
        id: pendingSend.id,
        text: pendingSend.text,
        canSteer: false,
        attachments: pendingSend.attachments.map(\.name)
      ))
    }
    composer.setQueue(queue)
    let now = Date().timeIntervalSince1970 * 1000
    var projected = transcript.rows(
      processEntryID: processEntryID,
      processStartID: processStartID,
      now: now,
      turnStartedAt: turnStartedAt
    )
    if processEntryID.isEmpty, let pendingSend { projected += pendingSend.rows(entries: transcript.entries) }
    for index in projected.indices where projected[index].kind == "attachments" {
      let entry = projected[index].entryID
      if projected[index].attachments.contains(where: { $0.localURI != nil }) {
        localAttachments[entry] = projected[index].attachments
      } else if let local = localAttachments[entry], local.count == projected[index].attachments.count {
        for item in projected[index].attachments.indices {
          let remote = projected[index].attachments[item]
          let convertedImage = local[item].image != nil && remote.image != nil
            && (local[item].fileName as NSString).deletingPathExtension == (remote.fileName as NSString).deletingPathExtension
          guard local[item].fileName == remote.fileName || convertedImage else { continue }
          projected[index].attachments[item].localURI = local[item].localURI
          projected[index].attachments[item].localID = local[item].id
        }
      }
    }
    localAttachments = localAttachments.filter { key, _ in projected.contains { $0.entryID == key } }
    updateWorkDurationTimer(rows: projected)
    let entryIDsToRetain = Set(projected.map(\.entryID))
    expandedMessages.formIntersection(entryIDsToRetain)
    expandedAttachments.formIntersection(entryIDsToRetain)
    collapsedMessageHeights = collapsedMessageHeights.filter { entryIDsToRetain.contains($0.key) }
    for row in projected where row.kind == "user" && collapsedMessageHeights[row.entryID] == nil {
      if let height = ChatSendHandoff.sourceHeight(id: row.entryID) {
        collapsedMessageHeights[row.entryID] = min(ChatMessageContent.maximumCollapsedHeight, max(68, height))
      }
    }
    let retainedIDs = Set(projected.map(\.id))
    projected = prepareHistory(projected)
    let liveEntryID = transcript.entries.last { $0.isRunning && (processEntryID.isEmpty || $0.id == processEntryID) }?.id
    let previousLive = self.liveEntryID
    let starting = previousLive == nil && liveEntryID != nil
    let nearTail = collection.contentSize.height - collection.bounds.height + collection.adjustedContentInset.bottom - previousOffset < CGFloat(ChatScroll.resumeDistance)
    let following = followsBottom || (starting && nearTail && !trackingPausedByGesture)
    followsBottom = following
    let completing = previousLive != nil && liveEntryID == nil
    // A stale running reply can complete together with an entire newer history.
    // Only fold in place when it is still the tail; bulk sync keeps the viewport anchor.
    let folding = completing && processEntryID.isEmpty && window != nil && projected.last?.entryID == previousLive
    let anchorID = folding && following
      ? projected.last(where: { $0.entryID == previousLive && $0.kind == "text" })?.id
      : collection.indexPathsForVisibleItems.sorted().compactMap { dataSource.itemIdentifier(for: $0) }.first(where: { id in projected.contains { $0.id == id } })
    let anchor = anchorID.flatMap { id -> (String, CGFloat)? in
      guard let index = dataSource.indexPath(for: id), let frame = collection.layoutAttributesForItem(at: index)?.frame else { return nil }
      return (id, frame.minY - previousOffset)
    }
    guard Set(projected.map(\.id)).count == projected.count else {
      applying = false
      displayError = LodyStrings.text("native.chat.error.transcript")
      return
    }
    if ChatHaptics.shouldNotifyTurnCompletion(
      previousLive: previousLive,
      nextLive: liveEntryID,
      processEntryID: processEntryID,
      inWindow: window != nil
    ) {
      turnFeedback.notificationOccurred(.success)
    }
    if liveEntryID != nil && processEntryID.isEmpty && window != nil && previousLive != liveEntryID {
      turnFeedback.prepare()
    }
    self.liveEntryID = liveEntryID
    let previous = rows
    prepareRowHeights(projected, previous: previous, animate: !folding)
    rows = Dictionary(projected.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    measurements = measurements.filter { retainedIDs.contains($0.key) }
    store.retain(retainedIDs)
    var snapshot = NSDiffableDataSourceSnapshot<String, String>()
    let grouped = Dictionary(grouping: projected, by: \.entryID)
    var entryIDs = transcript.entries.map(\.id)
    if let pendingSend, !entryIDs.contains(pendingSend.id) { entryIDs.append(pendingSend.id) }
    for id in entryIDs {
      guard let entryRows = grouped[id], !entryRows.isEmpty else { continue }
      if let duration = entryRows.firstIndex(where: { $0.kind == "duration" }) {
        // The local timer already occupies the reply section. Server takeover
        // replaces its contents without moving the timer across section insets.
        if duration > 0 {
          snapshot.appendSections([id])
          snapshot.appendItems(entryRows[..<duration].map(\.id), toSection: id)
        }
        let replySection = entryRows[duration].id
        snapshot.appendSections([replySection])
        snapshot.appendItems(entryRows[duration...].map(\.id), toSection: replySection)
      } else {
        snapshot.appendSections([id])
        snapshot.appendItems(entryRows.map(\.id), toSection: id)
      }
    }
    snapshot.reconfigureItems(projected.filter { previous[$0.id] != nil && previous[$0.id] != $0 }.map(\.id))
    empty.isHidden = !projected.isEmpty
    let updateLayout = { [self] in
      // Queue/attachment removal changes the composer's intrinsic height and
      // therefore the scroll inset used to calculate the flight destination.
      self.layoutIfNeeded()
      self.collection.collectionViewLayout.invalidateLayout()
      self.collection.layoutIfNeeded()
      self.updateBottomInset()
      if !folding || !self.followsBottom, let (id, offset) = anchor, let index = self.dataSource.indexPath(for: id), let frame = self.collection.layoutAttributesForItem(at: index)?.frame {
        self.collection.contentOffset.y = max(-self.collection.adjustedContentInset.top, frame.minY - offset)
      }
      if self.followsBottom { self.scrollToBottom() }
      if !projected.isEmpty { self.hasPositionedContent = true }
      if !self.rowHeights.isEmpty { self.startMotion() }
      self.updateBottomButton()
      self.deliverPendingContent()
    }
    let finish = { [weak self] in
      guard let self else { return }
      #if DEBUG
      self.recordHistoryCommit()
      self.streamPerformanceProbe?.commit(milliseconds: (CACurrentMediaTime() - commitStart) * 1000)
      #endif
      self.applying = false
      self.deliverPendingContent()
      if let tail = projected.last(where: { $0.streaming }) {
        self.renderTailLength = self.store.tailLength(id: tail.id)
      }
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

  private func updateWorkDurationTimer(rows: [ChatRow]) {
    let needsTimer = window != nil && ChatWorkDuration.needsTimer(rows)
    guard needsTimer else {
      workDurationTimer?.invalidate()
      workDurationTimer = nil
      return
    }
    guard workDurationTimer == nil else { return }
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.applyRows() }
    }
    workDurationTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }
}

private func textColor(for row: ChatRow) -> UIColor {
  if row.attention { return .systemOrange }
  if row.kind == "changes" || (row.kind == "summary" && row.running) { return .systemBlue }
  if row.kind == "user" { return .label }
  return .secondaryLabel
}

extension LodyChatView {
  /// Flow layout measures every item, including offscreen Markdown. Commit the
  /// recent tail first, then warm the same sizing cache in bounded main-run-loop
  /// slices before inserting history. UIKit text measurement stays on main.
  func prepareHistory(_ projected: [ChatRow]) -> [ChatRow] {
    historyPreparation?.cancel()
    historyPreparation = nil
    guard preparingHistory || (!hasPositionedContent && projected.count > 80) else { return projected }
    let width = max(1, collection.bounds.width - 40)
    if width != historyWidth {
      preparedHistory.removeAll()
      historyWidth = width
    }
    let historical = projected.dropLast(40)
    let remaining = historical.reversed().filter { preparedHistory[$0.id] != $0 }
    guard !remaining.isEmpty else {
      preparingHistory = false
      preparedHistory.removeAll()
      return projected
    }
    preparingHistory = true
    if window != nil {
      prepareHistorySlice(remaining, index: 0, width: width)
    }
    return Array(projected.suffix(40))
  }

  private func prepareHistorySlice(_ rows: [ChatRow], index: Int, width: CGFloat) {
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.window != nil else { return }
      self.historyPreparation = nil
      guard max(1, self.collection.bounds.width - 40) == width else {
        self.applyRows()
        return
      }
      let started = CACurrentMediaTime()
      let deadline = started + 0.004
      var next = index
      // ponytail: one row can exceed the budget; block-level measurement is the
      // next step if individual huge messages dominate, rather than history size.
      repeat {
        let row = rows[next]
        _ = self.rowHeight(row, width: width)
        self.preparedHistory[row.id] = row
        next += 1
      } while next < rows.count && CACurrentMediaTime() < deadline
      #if DEBUG
      self.historySliceTimes.append((CACurrentMediaTime() - started) * 1000)
      #endif
      if next == rows.count {
        self.applyRows()
      } else {
        self.prepareHistorySlice(rows, index: next, width: width)
      }
    }
    historyPreparation = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.008, execute: work)
  }

  #if DEBUG
  func recordHistoryCommit() {
    guard transcript.entries.first?.id == "perf-0", historyLoadStarted > 0 else { return }
    let elapsed = (CACurrentMediaTime() - historyLoadStarted) * 1000
    if historyFirstContent == 0, !rows.isEmpty {
      historyFirstContent = elapsed
      historyFirstRows = rows.count
    }
    guard !preparingHistory, rows.count == 15_000 else { return }
    let report: [String: Any] = [
      "firstContentMs": historyFirstContent, "firstRows": historyFirstRows,
      "completeMs": elapsed, "rows": rows.count,
      "sliceMs": historySliceTimes,
      "metric": "Native entries prop to layout completion; excludes JS fixture creation",
    ]
    if let data = try? JSONSerialization.data(withJSONObject: report, options: .sortedKeys) {
      try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("lody-chat-loading.json"), options: .atomic)
    }
    historyLoadStarted = 0
  }
  #endif
}
