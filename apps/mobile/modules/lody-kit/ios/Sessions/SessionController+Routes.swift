import UIKit

extension SessionController {
  func wireRouteEvents() {
    chat.imageSharingEnabled = true
    chat.onShareImage.onEventSent = { [weak self] body in
      self?.open("message-share", ["contentJSON": body["contentJSON"] as? String ?? ""], present: true)
    }
    chat.onActivityPress.onEventSent = { [weak self] body in
      guard let self, let entryId = body["entryId"] as? String, let itemId = body["itemId"] as? String else { return }
      if itemId.isEmpty { openProcess(entryId: entryId, startItemId: body["processStartId"] as? String ?? "") }
      else { activity(entryId: entryId, itemId: itemId) }
    }
    chat.onFilePress.onEventSent = { [weak self] body in
      self?.openFile(body["path"] as? String ?? "", line: (body["line"] as? NSNumber)?.intValue ?? 0)
    }
    chat.onTurnChangesPress.onEventSent = { [weak self] body in
      guard let self, let path = body["path"] as? String else { return }
      // Displayed native rows can lag the replica; the diff page validates its target.
      self.open("file-diff", ["sessionId": self.sessionId, "entryId": body["entryId"] as? String ?? "", "path": path],
                title: (path as NSString).lastPathComponent)
    }
  }

  var localProjectId: String? {
    guard let projectId = source.state.catalog.session(sessionId)?.projectId,
          let range = projectId.range(of: ":local:"), range.lowerBound > projectId.startIndex else { return nil }
    return String(projectId[range.upperBound...])
  }

  var reviewable: Bool {
    let projectId = source.state.catalog.session(sessionId)?.projectId ?? ""
    return workspaceAvailable && (localProjectId != nil || projectId.hasPrefix("github:"))
  }

  var browsable: Bool { workspaceAvailable && localProjectId != nil }

  private var workspaceAvailable: Bool {
    let creating = sender?.record?.creation != nil
    return !source.state.workspaceId.isEmpty && !creating && source.state.catalog.session(sessionId)?.archived == false
  }

  func openProjectFiles(title: String) {
    guard browsable else { return }
    let state = source.state
    open("files", ["workspaceId": state.workspaceId, "sessionId": sessionId, "userId": state.userId, "path": "", "title": title])
  }

  func openWorkspaceChanges() {
    guard reviewable else { return }
    open("workspace-changes", ["sessionId": sessionId])
  }

  private func openProcess(entryId: String, startItemId: String) {
    let page = ProcessController(entryId: entryId, startItemId: startItemId)
    processPage = page
    page.update(feed?.state.entriesJSON ?? "[]")
    page.onActivity = { [weak self, weak page] entry, item in self?.activity(entryId: entry, itemId: item, from: page) }
    page.onFile = { [weak self, weak page] path, line in self?.openFile(path, line: line, from: page) }
    LodyShell.shared.presentNative(
      page, title: LodyStrings.text(startItemId == "__tasks__" ? "process.tasks" : "process.title"),
      detents: [0.6, 1], grabber: true
    )
  }

  private func activity(entryId: String, itemId: String, from source: UIViewController? = nil) {
    let item = Self.item(in: feed?.state.entriesJSON ?? "[]", entryId: entryId, itemId: itemId)
    if item?["type"] as? String == "system_notice", item?["name"] as? String == "chat_failed" {
      open("agent-error", item?["meta"] as? [String: Any] ?? [:], present: true, from: source)
      return
    }
    guard feed?.state.status == "live" else {
      let alert = UIAlertController(
        title: LodyStrings.text("session.alert.syncing.title"), message: LodyStrings.text("session.alert.syncing.message"),
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: LodyStrings.text("common.ok"), style: .default))
      (source ?? self).present(alert, animated: true)
      return
    }
    guard let item else { return }
    if let permission = item["permission"] as? [String: Any], permission["pending"] as? Bool == true {
      do {
        openPermission(try SessionPermission.target(entryId: entryId, item: item, permission: permission))
      } catch {
        openPermission(nil)
        permissionPage?.showInvalidRequest(error.localizedDescription)
      }
      return
    }
    open("session-item-detail", [
      "sessionId": sessionId, "entryId": entryId, "itemIds": [itemId], "generation": feed?.generation ?? 0,
    ], present: true, from: source)
  }

  private func openFile(_ path: String, line: Int, from source: UIViewController? = nil) {
    guard !openingFile, !path.isEmpty else { return }
    openingFile = true
    Task { @MainActor [weak self] in
      guard let self else { return }
      defer { self.openingFile = false }
      var opened = false
      if let runtime = DataRuntime.current {
        opened = await FilePreview.open(sessionId: self.sessionId, path: path, line: line, runtime: runtime, from: source ?? self)
      }
      guard !opened, (source ?? self).view.window != nil else { return }
      self.open("file-content", ["sessionId": self.sessionId, "path": path, "line": line], present: true, from: source)
    }
  }

  func open(_ page: String, _ params: [String: Any], present: Bool = false, title: String? = nil, from source: UIViewController? = nil) {
    var options: [String: Any] = [:]
    if present { options["present"] = true }
    if let title { options["title"] = title }
    LodyShell.shared.openPage(page, params: Self.json(params), options: options, from: source ?? parent ?? self)
  }

  static func item(in entriesJSON: String, entryId: String, itemId: String) -> [String: Any]? {
    let entries = (try? JSONSerialization.jsonObject(with: Data(entriesJSON.utf8))) as? [[String: Any]] ?? []
    let items = entries.first { $0["id"] as? String == entryId }?["items"] as? [[String: Any]] ?? []
    return items.first { $0["itemId"] as? String == itemId }
  }
}

extension SessionController {
  func wireMentionEvents() {
    chat.onMentionBrowse.onEventSent = { [weak self] body in self?.browseMentions(body) }
  }

  func renderMentions(_ state: SessionListState, _ session: SessionItem) {
    guard !state.workspaceId.isEmpty, !state.userId.isEmpty else {
      guard mentions != nil else { return }
      mentions = nil
      chat.composer.setMentionItems("null")
      return
    }
    let source = MentionSource(
      workspaceId: state.workspaceId, sessionId: sessionId, cliType: session.cliType, agentType: session.agentType
    )
    guard mentions?.source != source else { return }
    let store = MentionCatalogStore(source: source)
    store.changed = { [weak self, weak store] in
      guard let self, let store, mentions === store else { return }
      chat.composer.setMentionItems(store.composerItemsJSON())
    }
    mentions = store
    chat.composer.setMentionItems(store.composerItemsJSON())
    store.preload()
  }

  private func browseMentions(_ body: [String: Any]) {
    guard let store = mentions, let category = body["category"] as? String,
          MentionCatalogStore.categories.contains(category) else { return }
    let picker = MentionPickerController(
      category: category, query: body["query"] as? String ?? "", store: store, initial: store.catalog(category)
    ) { [weak self, weak store] item in
      guard let self, let store, mentions === store else { return }
      mentionSequence += 1
      let result: [String: Any] = [
        "id": String(mentionSequence), "path": item.path,
        "item": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(item))) ?? NSNull(),
      ]
      chat.composer.setMentionResult(Self.json(result))
      if let page = parent, let container = page.navigationController { container.popToViewController(page, animated: true) }
    }
    LodyShell.shared.pushNative(
      picker, title: LodyStrings.text("native.chat.mention." + (ChatMentionItem.labels[category] ?? category)), from: parent ?? self
    )
  }
}
