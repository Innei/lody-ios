import UIKit
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
  private let form = CreateSessionController()
  private let transport = ShareSubmission()
  private let recovery = ShareRecovery()
  private var task: Task<Void, Never>?
  private var pending: [[String: Any]] = []
  private var submitted = false
  override func viewDidLoad() {
    super.viewDidLoad()
    let navigation = UINavigationController(rootViewController: form)
    addChild(navigation); view.addSubview(navigation.view)
    navigation.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      navigation.view.topAnchor.constraint(equalTo: view.topAnchor), navigation.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      navigation.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), navigation.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ]); navigation.didMove(toParent: self)
    form.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.close() })
    transport.onStatus = { [weak self] in self?.form.notice = $0 }
    form.onSubmit = { [weak self] draft in self?.send(draft) }
    ingest()
  }
  private func reloadPending() {
    pending = ShareStore.pending(user: form.form.userID, workspace: form.form.workspaceID)
    form.onRecovery = pending.isEmpty ? nil : { [weak self] in self?.recover() }
    form.render()
  }
  private func ingest() {
    form.busy = true
    task = Task { [weak self] in
      guard let self else { return }
      do {
        let snapshot = try ShareStore.currentSnapshot()
        guard snapshot["userId"] as? String != nil else {
          self.form.busy = false
          self.form.notice = LodyStrings.text("native.create.openSignIn")
          return
        }
        self.form.configure(snapshot)
        self.reloadPending()
        let providers = (self.extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let draft = try await ShareIngest.load(providers)
        try Task.checkCancellation()
        self.form.composer.setInitialDraft(draft.text)
        self.form.composer.setInitialAttachments(createJSON(draft.attachments))
        self.form.busy = false
      } catch {
        self.form.busy = false
        self.form.notice = LodyStrings.text("native.create.ingestError")
        self.form.submissionLocked = true
      }
    }
  }
  private func send(_ draft: [String: Any]) {
    guard !submitted else { return }
    submitted = true; form.busy = true; form.submissionLocked = true
    task = Task { [weak self] in
      guard let self else { return }
      do { self.finished(try await self.transport.submit(draft)) }
      catch {
        self.form.busy = false
        if Task.isCancelled { return }
        self.reloadPending()
        self.form.notice = error.localizedDescription
        // Only unlock if nothing durable was saved. Otherwise retry the receipt,
        // never allocate a second request ID for an uncertain submission.
        if self.pending.isEmpty {
          self.submitted = false
          self.form.submissionLocked = false
          self.form.composer.restoreRejectedDraft()
        }
      }
    }
  }
  private func finished(_ result: [String: Any], closeOnSuccess: Bool = true) {
    form.busy = false; reloadPending()
    if result["state"] as? String == "submitted" {
      form.notice = LodyStrings.text("native.create.submitted")
      if closeOnSuccess { extensionContext?.completeRequest(returningItems: nil) }
    } else if result["state"] as? String == "pending" {
      form.notice = LodyStrings.text("native.create.pending")
    } else {
      form.notice = LodyStrings.text("native.create.unconfirmed")
    }
  }
  private func recover() {
    recovery.present(on: form) { [weak self] result in
      guard let self else { return }
      self.finished(result, closeOnSuccess: self.submitted)
    }
  }
  private func close() { task?.cancel(); recovery.cancel(); extensionContext?.completeRequest(returningItems: nil) }
  override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); task?.cancel(); recovery.cancel() }
}
