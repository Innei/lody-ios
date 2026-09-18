import UIKit

struct ChatFindMatch: Equatable {
  let rowID: String
  let ordinal: Int
}

extension LodyChatView {
  func setFindRequest(_ json: String) {
    guard json != lastFindRequest else { return }
    lastFindRequest = json
    guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return }
    guard object["open"] as? Bool == true else { closeFind(); return }
    openFind(query: object["query"] as? String ?? "", keyboard: object["keyboard"] as? Bool == true)
  }

  func openFind(query: String, keyboard: Bool) {
    findBar.isHidden = false
    findBar.field.text = query
    findFocusRequest = keyboard
    findNeedsInitialPosition = true
    findSelection = nil
    findBar.changed = { [weak self] in
      self?.findNeedsInitialPosition = true
      self?.findSelection = nil
      self?.refreshFind()
    }
    findBar.move = { [weak self] in self?.moveFind($0) }
    findBar.dismiss = { [weak self] in self?.closeFind() }
    setNeedsLayout()
    refreshFind()
    layoutIfNeeded()
  }

  func closeFind() {
    findBar.field.resignFirstResponder()
    findBar.isHidden = true
    findMatches = []
    findSelection = nil
    findNeedsInitialPosition = false
    findFocusRequest = nil
    for view in findHighlightedViews.allObjects { ChatFindHighlight.apply(to: view, query: "", active: nil) }
    findHighlightedViews.removeAllObjects()
    setNeedsLayout()
  }

  func layoutFind() {
    let height: CGFloat = findBar.isHidden ? 0 : findBar.preferredHeight
    findBar.frame = CGRect(x: safeAreaInsets.left, y: safeAreaInsets.top,
      width: bounds.width - safeAreaInsets.left - safeAreaInsets.right, height: height)
    if collection.contentInset.top != height { collection.contentInset.top = height }
    collection.verticalScrollIndicatorInsets.top = height
    if let keyboard = findFocusRequest, let window {
      findFocusRequest = nil
      if keyboard { findBar.field.becomeFirstResponder() }
      else { window.endEditing(true) }
    }
    refreshFindHighlights()
  }

  func refreshFind() {
    guard !findBar.isHidden, !applying else { return }
    let query = (findBar.field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let ids = dataSource.snapshot().itemIdentifiers
    let oldSelection = findSelection
    findMatches = ids.flatMap { id -> [ChatFindMatch] in
      guard let row = rows[id], ["user", "text", "thought"].contains(row.kind) else { return [] }
      let text = SessionProse.text(row.text, role: row.kind == "user" ? "user" : "assistant")
      return TextSearch.ranges(in: text, query: query).indices.map { ChatFindMatch(rowID: id, ordinal: $0) }
    }
    if let oldSelection, findMatches.contains(oldSelection) { findSelection = oldSelection }
    else { findSelection = findMatches.last }
    findBar.update(current: findSelection.flatMap { findMatches.firstIndex(of: $0) }.map { $0 + 1 } ?? 0,
      total: findMatches.count, partial: hasEarlierHistory)
    refreshFindHighlights()
    if findNeedsInitialPosition, !ids.isEmpty {
      findNeedsInitialPosition = false
      // TODO: Extend the history window when supporting older search targets.
      // ponytail: navigate expanded rows in this window only; otherwise keep the latest result.
      if findSelection != nil { scrollToFind() }
    }
  }

  func moveFind(_ direction: Int) {
    guard !findMatches.isEmpty else { return }
    let current = findSelection.flatMap { findMatches.firstIndex(of: $0) } ?? 0
    findSelection = findMatches[(current + direction + findMatches.count) % findMatches.count]
    findBar.update(current: (findMatches.firstIndex(of: findSelection!) ?? 0) + 1,
      total: findMatches.count, partial: hasEarlierHistory)
    scrollToFind()
  }

  private func scrollToFind() {
    guard let match = findSelection, let index = dataSource.indexPath(for: match.rowID) else { return }
    pauseTracking()
    layoutIfNeeded()
    collection.scrollToItem(at: index, at: .centeredVertically, animated: false)
    collection.layoutIfNeeded()
    refreshFindHighlights()
    if let cell = collection.cellForItem(at: index),
       let rect = ChatFindHighlight.apply(to: cell.contentView,
         query: (findBar.field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines), active: match.ordinal, reveal: true) {
      collection.scrollRectToVisible(cell.contentView.convert(rect, to: collection).insetBy(dx: 0, dy: -12), animated: false)
    }
  }

  func refreshFindHighlights() {
    guard !findBar.isHidden else { return }
    let query = (findBar.field.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    for cell in collection.visibleCells {
      guard let index = collection.indexPath(for: cell), let id = dataSource.itemIdentifier(for: index) else { continue }
      let searchable = rows[id].map { ["user", "text", "thought"].contains($0.kind) } == true
      findHighlightedViews.add(cell.contentView)
      ChatFindHighlight.apply(to: cell.contentView, query: searchable ? query : "",
        active: findSelection?.rowID == id ? findSelection?.ordinal : nil)
    }
  }
}
