import QuickLook
import UIKit

/// Quick Look provides video playback, document previews and the system share action.
@MainActor
final class SessionFilePreviewController: QLPreviewController, QLPreviewControllerDataSource, @MainActor QLPreviewControllerDelegate {
  private let file: ChatMessageAttachment
  private let workspace: String
  private let session: String
  private let directory = ContentPreviewCoordinator.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
  private var url: URL?
  private var download: Task<Void, Never>?
  private var fixtureAttempt = 0

  init(file: ChatMessageAttachment, workspace: String, session: String) {
    self.file = file
    self.workspace = workspace
    self.session = file.storageSessionId ?? session
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    dataSource = self
    delegate = self
    load()
  }

  private func load() {
    download?.cancel()
    var loading = UIContentUnavailableConfiguration.loading()
    loading.text = String(localized: "native.attachment.preview.loading", bundle: .lody)
    loading.background.backgroundColor = .systemBackground
    loading.button.title = String(localized: "native.close", bundle: .lody)
    loading.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.dismiss(animated: true) }
    contentUnavailableConfiguration = loading
    fixtureAttempt += 1
    let attempt = fixtureAttempt
    download = Task { [weak self, file, workspace, session, directory] in
      do {
        guard file.transport == nil || file.transport == "r2" else {
          throw SessionAttachments.error(String(localized: "native.attachment.error.pending", bundle: .lody))
        }
        let url: URL
        if LodyUIVerify.enabled, session == "ui-verify-attachments" {
          try await Task.sleep(for: .milliseconds(file.id == "cancel" ? 4000 : 1200))
          url = try FilePreviewFixture.attachment(file.id, attempt: attempt, directory: directory)
        } else {
          url = try await SessionAttachments.download(workspace: workspace, session: session, fileId: file.id,
            fileName: file.fileName, sizeBytes: file.sizeBytes, directory: directory)
        }
        try Task.checkCancellation()
        guard let self else { try? FileManager.default.removeItem(at: directory); return }
        self.url = url
        self.contentUnavailableConfiguration = nil
        self.reloadData()
      } catch {
        try? FileManager.default.removeItem(at: directory)
        guard !Task.isCancelled, let self else { return }
        var failed = UIContentUnavailableConfiguration.empty()
        failed.background.backgroundColor = .systemBackground
        failed.image = UIImage(systemName: "doc.badge.ellipsis")
        failed.text = file.fileName
        failed.secondaryText = error.localizedDescription
        failed.secondaryButton.title = String(localized: "native.close", bundle: .lody)
        failed.secondaryButtonProperties.primaryAction = UIAction { [weak self] _ in self?.dismiss(animated: true) }
        if file.transport != "local" {
          failed.button.title = String(localized: "native.attachment.preview.retry", bundle: .lody)
          failed.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.load() }
        }
        self.contentUnavailableConfiguration = failed
      }
    }
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    download?.cancel()
    try? FileManager.default.removeItem(at: directory)
  }

  deinit {
    download?.cancel()
    try? FileManager.default.removeItem(at: directory)
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { url == nil ? 0 : 1 }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    url! as NSURL
  }
}
