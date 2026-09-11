import UIKit

extension LodyChatView {
  var composerInset: CGFloat {
    processEntryID.isEmpty ? max(0, bounds.maxY - composer.frame.minY - collection.safeAreaInsets.bottom) + 8 : 0
  }

  @discardableResult
  func updateBottomInset() -> Bool {
    let base = composerInset
    var space: CGFloat = 0
    if let id = anchoredUserID, let index = dataSource.indexPath(for: id),
       let frame = collection.layoutAttributesForItem(at: index)?.frame {
      let naturalBottom = collection.contentSize.height - collection.bounds.height + collection.safeAreaInsets.bottom + base
      space = max(0, frame.minY - collection.adjustedContentInset.top - naturalBottom)
    }
    let bottom = base + space
    // Compensate even one pixel of reply growth: at 3x, a 0.5pt deadband
    // lets the bottom follower move the pinned turn by 1px and back again.
    guard collection.contentInset.bottom != bottom else { return false }
    collection.contentInset.bottom = bottom
    collection.verticalScrollIndicatorInsets.bottom = base
    return true
  }

  func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
    guard let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id] else { return false }
    if let cell = collectionView.cellForItem(at: indexPath) as? ChatCell, cell.expandable && !cell.expanded { return true }
    return row.kind == "changes" || row.actionable || row.image != nil
  }

  func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    if let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id], row.kind == "changes", let file = row.fileDiff {
      onTurnChangesPress(["entryId": row.entryID, "path": file.path])
      return
    }
    collectionView.deselectItem(at: indexPath, animated: false)
    if let cell = collectionView.cellForItem(at: indexPath) as? ChatCell,
       cell.expandable, !cell.expanded, let row = cell.row {
      toggleExpansion(row)
      return
    }
    if let cell = collectionView.cellForItem(at: indexPath) as? ChatImageCell, let controller = presenter() {
      pauseTracking()
      cell.presentPreview(from: controller)
      return
    }
    guard let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id], row.actionable else { return }
    if let pendingSend, id == pendingSend.id + ":pending", pendingSend.failed == true {
      onRetrySend([:])
      return
    }
    if let pendingSend, id == pendingSend.id + ":pending", pendingSend.reconnect == true {
      onReconnect([:])
      return
    }
    onActivityPress(["entryId": row.entryID, "itemId": row.itemID, "processStartId": row.processStartID])
  }

  func toggleExpansion(_ row: ChatRow) {
    guard let index = dataSource.indexPath(for: row.id), let cell = collection.cellForItem(at: index) else { return }
    pauseTracking()
    ChatSendHandoff.cancel(id: row.entryID)
    if let cell = cell as? ChatMessageAttachmentsCell {
      if !expandedAttachments.insert(row.entryID).inserted { expandedAttachments.remove(row.entryID) }
      cell.expanded = expandedAttachments.contains(row.entryID)
    } else if let cell = cell as? ChatCell {
      if !expandedMessages.insert(row.entryID).inserted { expandedMessages.remove(row.entryID) }
      cell.expanded = expandedMessages.contains(row.entryID)
    }
    let offset = collection.contentOffset
    let update = {
      self.collection.collectionViewLayout.invalidateLayout()
      self.collection.layoutIfNeeded()
      cell.setNeedsLayout()
      cell.layoutIfNeeded()
      self.updateBottomInset()
      self.collection.contentOffset.y = min(self.bottomOffset, max(-self.collection.adjustedContentInset.top, offset.y))
    }
    if UIAccessibility.isReduceMotionEnabled {
      update()
      UIAccessibility.post(notification: .layoutChanged, argument: nil)
    } else {
      UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: update) { _ in
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
      }
    }
  }

  func deselectFileOnReturn(animated: Bool, coordinator: UIViewControllerTransitionCoordinator?) {
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

  func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
    guard scrollView === collection else { return true }
    scrollingToTop = true
    pauseTracking()
    return true
  }

  func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
    guard scrollView === collection else { return }
    scrollingToTop = false
    commitPreparedHistory()
  }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    guard scrollView === collection else { return }
    scrollingToTop = false
    pauseTracking()
  }

  func pauseTracking() {
    followsBottom = false
    trackingPausedByGesture = true
    sendScroll = nil
    awaitingUserAnchor = false
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard scrollView === collection else { return }
    updateBottomButton()
    prefetchHistoryIfNeeded()
  }

  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
    guard scrollView === collection, !decelerate else { return }
    commitPreparedHistory()
    resumeTrackingAtBottom()
  }

  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    guard scrollView === collection else { return }
    commitPreparedHistory()
    resumeTrackingAtBottom()
  }

  func resumeTrackingAtBottom() {
    guard bottomOffset - collection.contentOffset.y <= 1 else { return }
    trackingPausedByGesture = false
    followsBottom = true
    scrollToBottom()
  }

  var bottomOffset: CGFloat {
    CGFloat(ChatScroll.bottom(contentHeight: Double(collection.contentSize.height),
      viewportHeight: Double(collection.bounds.height), topInset: Double(collection.adjustedContentInset.top),
      bottomInset: Double(collection.adjustedContentInset.bottom)))
  }

  func updateBottomButton() {
    let bottom = bottomOffset
    let visible = processEntryID.isEmpty && !followsBottom && bottom - collection.contentOffset.y > CGFloat(ChatScroll.resumeDistance)
    guard visible != bottomButton.isUserInteractionEnabled else { return }
    bottomButton.isUserInteractionEnabled = visible
    bottomButton.accessibilityElementsHidden = !visible
    UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
      self.bottomButton.alpha = visible ? 1 : 0
    }
  }

  func scrollToBottom() {
    guard !movingLayout, !collection.isDragging, !collection.isDecelerating else { return }
    if !hasPositionedContent || UIAccessibility.isReduceMotionEnabled || window == nil {
      collection.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
    } else if abs(collection.contentOffset.y - bottomOffset) > 0.5 {
      startMotion()
    }
  }

  func startMotion() {
    guard motionLink == nil, window != nil else { return }
    let link = CADisplayLink(target: ChatMotionTarget(self), selector: #selector(ChatMotionTarget.tick(_:)))
    motionTime = CACurrentMediaTime()
    motionLink = link
    link.add(to: .main, forMode: .common)
  }

  func advanceMotion(_ link: CADisplayLink) {
    guard !applying else { motionTime = link.targetTimestamp; return }
    let elapsed = min(1.0 / 30, max(0, link.targetTimestamp - motionTime))
    motionTime = link.targetTimestamp
    let reduce = UIAccessibility.isReduceMotionEnabled
    movingLayout = true
    if !rowHeights.isEmpty {
      let anchor = visibleAnchor()
      for (id, height) in rowHeights {
        let current = reduce ? height.target : CGFloat(ChatScroll.advance(
          Double(height.current), toward: Double(height.target), elapsed: elapsed, response: 0.06))
        rowHeights[id] = current == height.target ? nil : (current, height.target, height.width)
      }
      collection.collectionViewLayout.invalidateLayout()
      collection.layoutIfNeeded()
      updateBottomInset()
      restoreAnchor(anchor)
    }
    let tracking = followsBottom && !collection.isDragging && !collection.isDecelerating
    if tracking {
      let y: CGFloat
      if let sendScroll, !reduce {
        // Finish the list movement before the flying bubble lands.
        let progress = min(1, max(0, (link.targetTimestamp - sendScroll.started) / 0.25))
        let eased = CGFloat(1 - pow(1 - progress, 3))
        y = sendScroll.offset + (bottomOffset - sendScroll.offset) * eased
        if progress == 1 { self.sendScroll = nil }
      } else {
        y = reduce ? bottomOffset : CGFloat(ChatScroll.advance(
          Double(collection.contentOffset.y), toward: Double(bottomOffset), elapsed: elapsed, response: 0.10,
          minimumStep: 1 / Double(window?.screen.scale ?? 3)))
      }
      collection.setContentOffset(CGPoint(x: 0, y: y), animated: false)
    }
    deliverPendingContent()
    movingLayout = false
    updateBottomButton()
    if rowHeights.isEmpty && (!tracking || abs(collection.contentOffset.y - bottomOffset) <= 0.5) {
      link.invalidate()
      motionLink = nil
    }
  }

  func visibleAnchor() -> (String, CGFloat)? {
    for index in collection.indexPathsForVisibleItems.sorted() {
      if let id = dataSource.itemIdentifier(for: index), let frame = collection.layoutAttributesForItem(at: index)?.frame {
        return (id, frame.minY - collection.contentOffset.y)
      }
    }
    return nil
  }

  func restoreAnchor(_ anchor: (String, CGFloat)?) {
    guard let (id, y) = anchor, let index = dataSource.indexPath(for: id),
          let frame = collection.layoutAttributesForItem(at: index)?.frame else { return }
    collection.contentOffset.y = max(-collection.adjustedContentInset.top, frame.minY - y)
  }

  func prepareRowHeights(_ projected: [ChatRow], previous: [String: ChatRow], animate: Bool) {
    let ids = Set(projected.map(\.id))
    rowHeights = rowHeights.filter { ids.contains($0.key) }
    guard animate, hasPositionedContent, window != nil, !UIAccessibility.isReduceMotionEnabled else {
      rowHeights.removeAll()
      return
    }
    let width = max(1, collection.bounds.width - 40)
    for row in projected where row != previous[row.id] {
      // Long replies grow at the content-commit cadence. Animating their height
      // would invalidate the entire collection at display refresh rate; the
      // bottom follower and block opacity animation already keep motion smooth.
      if (row.kind == "text" || row.kind == "thought") && row.text.utf16.count > ChatStream.blockAnimationLength {
        rowHeights[row.id] = nil
        continue
      }
      guard row.streaming || previous[row.id]?.streaming == true else {
        rowHeights[row.id] = nil
        continue
      }
      let oldFrame = dataSource.indexPath(for: row.id).flatMap { collection.layoutAttributesForItem(at: $0)?.frame }
      let current = rowHeights[row.id]?.current ?? oldFrame?.height ?? 12
      let target = rowHeight(row, width: width)
      if abs(current - target) > 0.5 { rowHeights[row.id] = (current, target, width) }
      else { rowHeights[row.id] = nil }
    }
  }

  func measure(_ row: ChatRow, width: CGFloat) -> CGFloat {
    if let image = row.image {
      let height = ChatImageCell.size(image, width: width).height
      return height
    }
    let textWidth = ChatCell.textWidth(row, width: width)
    if row.kind == "text" || row.kind == "thought" {
      return store.height(id: row.id, text: row.text, secondary: row.kind == "thought", streaming: row.streaming, width: textWidth)
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

  func collectionView(_ collectionView: UICollectionView, targetContentOffsetForProposedContentOffset proposed: CGPoint) -> CGPoint {
    guard let (id, offset) = historyLayoutAnchor,
          let index = dataSource.indexPath(for: id),
          let frame = collectionView.layoutAttributesForItem(at: index)?.frame else { return proposed }
    return CGPoint(x: proposed.x, y: max(-collectionView.adjustedContentInset.top, frame.minY - offset))
  }

  func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
    CGSize(width: collectionView.bounds.width, height: section == 0 && processEntryID.isEmpty && hasPagedHistory ? 48 : 0)
  }

  func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
    let width = max(1, collectionView.bounds.width - 40)
    guard let id = dataSource.itemIdentifier(for: indexPath), let row = rows[id] else { return CGSize(width: width, height: 0) }
    if let height = rowHeights[id], height.width == width {
      return CGSize(width: width, height: height.current)
    }
    rowHeights[id] = nil
    return CGSize(width: width, height: rowHeight(row, width: width))
  }

  func rowHeight(_ row: ChatRow, width: CGFloat, previousKind: String? = nil) -> CGFloat {
    if row.kind == "attachments" {
      return ChatMessageAttachmentsCell.height(count: row.attachments.count, width: width, expanded: expandedAttachments.contains(row.entryID))
    }
    if row.kind == "meta" { return ChatMetaCell.height(for: row, width: width, traits: traitCollection) }
    if row.kind == "changesHeader" { return 28 }
    if row.kind == "changes" { return ChatFileCell.rowHeight() }
    let measured = measure(row, width: width)
    if row.kind == "user" {
      return ChatMessageContent.height(textHeight: measured,
        limit: collapsedMessageHeights[row.entryID] ?? ChatMessageContent.maximumCollapsedHeight,
        expanded: expandedMessages.contains(row.entryID)) + 24
    }
    // Process and pending status rows are buttons. Duration stays copy-sized
    // even after the folded process makes it tappable — a 44 pt floor would
    // leave an empty gap between the timer and the hairline.
    let tapFloor = row.kind != "duration" && (row.actionable || row.kind == "summary" || row.kind == "pending")
    return max(tapFloor ? 44 : 0, measured + ChatCell.rowExtra(for: row, previousKind: previousKind ?? kind(before: row.id)))
  }

  func kind(before id: String) -> String? {
    let ids = dataSource.snapshot().itemIdentifiers
    guard let index = ids.firstIndex(of: id), index > 0 else { return nil }
    return rows[ids[index - 1]]?.kind
  }

  func setAttachmentContext(_ json: String) {
    guard let data = json.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
    let workspace = value["workspaceId"] ?? "", session = value["sessionId"] ?? ""
    guard workspace != imageWorkspace || session != imageSession else { return }
    imageWorkspace = workspace; imageSession = session
    collection.reloadData()
  }

  func presenter() -> UIViewController? {
    var responder: UIResponder? = next
    while let current = responder {
      if let controller = current as? UIViewController { return controller.presentedViewController ?? controller }
      responder = current.next
    }
    return window?.rootViewController
  }

  func deliverPendingContent() {
    guard window != nil, hasAppeared, !applying else { return }
    collection.layoutIfNeeded()
    let distance = followsBottom ? bottomOffset - collection.contentOffset.y : 0
    if let handoffID, followsBottom, abs(distance) > 0.5,
       ChatSendHandoff.isWaiting(id: handoffID) || ChatSendHandoff.hasWaitingAttachments(id: handoffID) {
      sendScroll = (CACurrentMediaTime(), collection.contentOffset.y)
      startMotion()
    }
    for cell in collection.visibleCells {
      if let attachments = cell as? ChatMessageAttachmentsCell {
        attachments.layoutIfNeeded()
        attachments.deliverPendingAttachments(scrollDistance: distance)
      }
      // A steered queue row flies under its own entry id, so any landed user row
      // with a waiting flight is a destination, not only the pending send.
      guard let cell = cell as? ChatCell, let row = cell.row, row.kind == "user",
            row.entryID == handoffID || ChatSendHandoff.isWaiting(id: row.entryID) else { continue }
      cell.layoutIfNeeded()
      let distance = followsBottom ? bottomOffset - collection.contentOffset.y : 0
      if ChatSendHandoff.isWaiting(id: row.entryID), followsBottom, abs(distance) > 0.5 {
        sendScroll = (CACurrentMediaTime(), collection.contentOffset.y)
        startMotion()
      }
      ChatSendHandoff.deliver(id: row.entryID, to: cell.messageContent, scrollDistance: distance)
    }
  }
}

@MainActor
private final class ChatMotionTarget: NSObject {
  weak var view: LodyChatView?
  init(_ view: LodyChatView) { self.view = view }
  @objc func tick(_ link: CADisplayLink) {
    guard let view else { link.invalidate(); return }
    view.advanceMotion(link)
  }
}

#if DEBUG
// Opt-in, offline fixture geometry only. No message text or account data leaves
// the view. The independent sampler observes UIKit, not the motion's targets.
@MainActor
final class ChatScrollProbe: NSObject {
  weak var view: LodyChatView?
  private var link: CADisplayLink?
  private var samples: [[String: Any]] = []
  private let id = UUID().uuidString
  private let started = CACurrentMediaTime()
  init(_ view: LodyChatView) {
    self.view = view
    super.init()
    let link = CADisplayLink(target: self, selector: #selector(sample(_:)))
    self.link = link
    link.add(to: .main, forMode: .common)
  }
  @objc private func sample(_ link: CADisplayLink) {
    guard let view, samples.count < 10800 else { stop(); return }
    guard view.rows.keys.contains(where: { $0.hasPrefix("scroll-") || $0.hasPrefix("perf-") }) else { return }
    let list = view.collection
    var visible: [String: Any] = [:]
    for index in list.indexPathsForVisibleItems {
      guard let id = view.dataSource.itemIdentifier(for: index),
            id.hasPrefix("scroll-") || id.hasPrefix("perf-"),
            let cell = list.cellForItem(at: index) else { continue }
      let frame = cell.layer.presentation()?.frame ?? cell.frame
      let offset = list.layer.presentation()?.bounds.minY ?? list.contentOffset.y
      visible[id] = ["y": frame.minY - offset, "height": frame.height]
    }
    samples.append(["t": link.timestamp - started, "offset": list.contentOffset.y,
      "bottom": view.bottomOffset, "contentHeight": list.contentSize.height,
      "inset": list.adjustedContentInset.bottom, "following": view.followsBottom,
      "dragging": list.isDragging || list.isDecelerating,
      "touching": list.isTracking, "panY": list.panGestureRecognizer.translation(in: view.window).y,
      "paging": view.preparingHistory, "scrollingToTop": view.scrollingToTop,
      "count": view.rows.count, "rows": visible])
  }
  func stop() {
    link?.invalidate(); link = nil
    guard !samples.isEmpty else { return }
    let report: [String: Any] = ["host": view?.processEntryID.isEmpty == false ? "process" : "chat", "samples": samples]
    if let data = try? JSONSerialization.data(withJSONObject: report) {
      try? data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("lody-scroll-\(id).json"), options: .atomic)
    }
    samples.removeAll()
  }
}
#endif

#if DEBUG
// Measures main-run-loop delivery, not GPU presentation. No text is recorded.
@MainActor
final class ChatPerformanceProbe: NSObject {
  private weak var view: LodyChatView?
  private var link: CADisplayLink?
  private let requested = CACurrentMediaTime()
  private var started: Double = 0
  private var previous: Double = 0
  private var origin: CGFloat = 0
  private var samples: [[String: Double]] = []
  private var memory: [[String: Double]] = []
  private var nextMemory: Double = 0
  private var baseline = 0.0

  init(_ view: LodyChatView) {
    self.view = view
    super.init()
    view.scrollProbe?.stop(); view.scrollProbe = nil
    view.setNavigationSubtitle("Preparing · 20s · 8,000 pt/s")
    let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
    self.link = link
    link.add(to: .main, forMode: .common)
  }

  @objc private func tick(_ link: CADisplayLink) {
    guard let view, view.window != nil,
          UIApplication.shared.applicationState == .active else { stop(); return }
    let now = CACurrentMediaTime()
    let list = view.collection
    if started == 0 {
      guard now - requested < 300 else {
        view.setNavigationSubtitle("Benchmark failed: loading timeout")
        stop(); return
      }
      if view.hasEarlierHistory {
        // Benchmark setup traverses the same top-edge pagination as a reader.
        // The timed scrolling phase still runs against the complete dataset.
        view.setNavigationSubtitle("Loading history · \(view.rows.count) rows")
        view.pauseTracking()
        if !view.preparingHistory && !view.applying {
          list.setContentOffset(CGPoint(x: 0, y: -list.adjustedContentInset.top), animated: false)
          view.prefetchHistoryIfNeeded()
        }
        return
      }
      guard view.transcript.entries.count == 10_000,
            !view.preparingHistory,
            view.transcript.entries.first?.id == "perf-0",
            !view.applying, !view.rendering, !view.decoding,
            view.hasPositionedContent, view.motionLink == nil,
            now - requested >= 2 else { return }
      view.pauseTracking()
      list.setContentOffset(CGPoint(x: 0, y: view.bottomOffset), animated: false)
      origin = list.contentOffset.y
      started = now
      previous = now
      baseline = Self.footprint()
      memory.append(["t": 0, "mib": baseline])
      view.setNavigationSubtitle("Running · 20s · 8,000 pt/s")
      return
    }
    let elapsed = now - started
    let visible = list.indexPathsForVisibleItems.map(\.section)
    samples.append(["t": elapsed, "dt": now - previous,
      "budget": link.targetTimestamp - link.timestamp,
      "offset": list.contentOffset.y,
      "firstSection": Double(visible.min() ?? -1), "lastSection": Double(visible.max() ?? -1)])
    previous = now
    if elapsed >= nextMemory {
      memory.append(["t": elapsed, "mib": Self.footprint()])
      nextMemory = elapsed + 0.25
    }
    if elapsed >= 20 {
      finish(elapsed: elapsed)
      return
    }
    // A repeatable continuous scroll over the real production collection. The
    // dataset has 10k entries; this timed run does not claim to visit every row.
    let travel = min(elapsed, 20 - elapsed) * 8_000
    let target = max(-list.adjustedContentInset.top, origin - CGFloat(travel))
    list.setContentOffset(CGPoint(x: 0, y: target), animated: false)
  }

  private func finish(elapsed: Double) {
    guard let view else { stop(); return }
    let fps = Double(samples.count) / elapsed
    let peak = memory.map { $0["mib"]! }.max() ?? -1
    let report: [String: Any] = [
      "metric": "CADisplayLink main-run-loop FPS; not GPU presented FPS",
      "configuration": "Debug", "device": UIDevice.current.model,
      "systemVersion": UIDevice.current.systemVersion,
      "maximumFramesPerSecond": view.window?.screen.maximumFramesPerSecond ?? 0,
      "entries": view.transcript.entries.count, "rows": view.rows.count,
      "seconds": elapsed, "pointsPerSecond": 8000, "fps": fps,
      "baselineMiB": baseline, "peakMiB": peak, "endMiB": Self.footprint(),
      "memoryMetric": "App process TASK_VM_INFO phys_footprint; sampled every 250ms",
      "samples": samples, "memory": memory,
    ]
    do {
      let data = try JSONSerialization.data(withJSONObject: report, options: .sortedKeys)
      try data.write(to: FileManager.default.temporaryDirectory
        .appendingPathComponent("lody-chat-performance-\(UUID().uuidString).json"), options: .atomic)
      view.setNavigationSubtitle(String(format: "%.1f FPS · peak %.1f MiB", fps, peak))
    } catch {
      view.setNavigationSubtitle("Benchmark failed: report write error")
    }
    stop()
  }

  func stop() {
    link?.invalidate(); link = nil
    samples.removeAll(); memory.removeAll()
  }

  private static func footprint() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
  }
}
#endif
