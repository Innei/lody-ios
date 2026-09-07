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
    guard abs(collection.contentInset.bottom - bottom) > 0.5 else { return false }
    collection.contentInset.bottom = bottom
    collection.verticalScrollIndicatorInsets.bottom = base
    return true
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

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    guard scrollView === collection else { return }
    pauseTracking()
  }

  func pauseTracking() {
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

  func resumeTrackingAtBottom() {
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

  var bottomOffset: CGFloat {
    CGFloat(ChatScroll.bottom(contentHeight: Double(collection.contentSize.height),
      viewportHeight: Double(collection.bounds.height), topInset: Double(collection.adjustedContentInset.top),
      bottomInset: Double(collection.adjustedContentInset.bottom)))
  }

  func updateBottomButton() {
    let bottom = bottomOffset
    let visible = processEntryID.isEmpty && bottom - collection.contentOffset.y > CGFloat(ChatScroll.resumeDistance)
    guard visible != bottomButton.isUserInteractionEnabled else { return }
    bottomButton.isUserInteractionEnabled = visible
    bottomButton.accessibilityElementsHidden = !visible
    UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
      self.bottomButton.alpha = visible ? 1 : 0
    }
  }

  func scrollToBottom() {
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

  func measure(_ row: ChatRow, width: CGFloat) -> CGFloat {
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
      return CGSize(width: width, height: ChatFileCell.rowHeight())
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

  func presenter() -> UIViewController? {
    var responder: UIResponder? = next
    while let current = responder {
      if let controller = current as? UIViewController { return controller.presentedViewController ?? controller }
      responder = current.next
    }
    return window?.rootViewController
  }

  func deliverPendingContent() {
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
}
