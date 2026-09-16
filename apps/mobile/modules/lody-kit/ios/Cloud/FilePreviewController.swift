import QuickLook
import UIKit

@MainActor
enum FilePreview {
  static func read(sessionId: String, path: String, runtime: DataRuntime) async throws -> String {
    let payload = String(
      data: try JSONSerialization.data(withJSONObject: ["sessionId": sessionId, "path": path]),
      encoding: .utf8
    )!
    if let response = FilePreviewFixture.response(payload) {
      let delay = payload.contains("document.pdf") ? 0.0 : 5.0
      if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
      try Task.checkCancellation()
      return response
    }
    return try await runtime.command("readFile", payload: payload)
  }

  static func resolve(href: String, from path: String) -> String {
    if href.hasPrefix("/") { return href }
    if href.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil { return href }
    let parent = (path as NSString).deletingLastPathComponent
    if parent.isEmpty || parent == "." { return href }
    return parent + "/" + href
  }

  static func presentsQuickLook(_ path: String) -> Bool {
    switch ChatFileLink.iconName(for: path) {
    case "image", "pdf", "video", "audio", "zip", "word", "powerpoint", "table":
      return true
    default:
      return false
    }
  }

  static func open(
    sessionId: String,
    path: String,
    line: Int,
    runtime: DataRuntime,
    from controller: UIViewController
  ) async {
    guard !sessionId.isEmpty, !path.isEmpty else { return }
    if presentsQuickLook(path) {
      await FileQuickLookController.present(
        sessionId: sessionId, path: path, runtime: runtime, from: controller
      )
      return
    }
    await FilePreviewController.present(
      sessionId: sessionId, path: path, line: line, runtime: runtime, from: controller
    )
  }
}

@MainActor
final class FileQuickLookController: QLPreviewController, QLPreviewControllerDataSource, @MainActor QLPreviewControllerDelegate {
  private let sessionId: String
  private let path: String
  private let runtime: DataRuntime
  private var onClose: (() -> Void)?
  private var loadTask: Task<Void, Never>?
  private var previewURL: URL?
  private let directory = ContentPreview.root.appendingPathComponent(UUID().uuidString, isDirectory: true)
  private let spinner = UIActivityIndicatorView(style: .medium)

  static func present(
    sessionId: String,
    path: String,
    runtime: DataRuntime,
    from controller: UIViewController
  ) async {
    await withCheckedContinuation { continuation in
      let preview = FileQuickLookController(sessionId: sessionId, path: path, runtime: runtime)
      preview.onClose = { continuation.resume() }
      preview.modalPresentationStyle = .pageSheet
      if let sheet = preview.sheetPresentationController {
        sheet.detents = [.large()]
        sheet.prefersGrabberVisible = true
      }
      var host = controller
      while let presented = host.presentedViewController { host = presented }
      host.present(preview, animated: true)
    }
  }

  private init(sessionId: String, path: String, runtime: DataRuntime) {
    self.sessionId = sessionId
    self.path = path
    self.runtime = runtime
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    dataSource = self
    delegate = self
    spinner.color = .secondaryLabel
    spinner.accessibilityIdentifier = "file-loading"
    spinner.accessibilityLabel = LodyStrings.text("native.file.reading")
    spinner.hidesWhenStopped = true
    view.addSubview(spinner)
    load()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    spinner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
  }

  private func load() {
    loadTask?.cancel()
    var loading = UIContentUnavailableConfiguration.loading()
    loading.text = LodyStrings.text("native.file.reading")
    loading.background.backgroundColor = .systemBackground
    loading.button.title = LodyStrings.text("native.close")
    loading.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.dismiss(animated: true) }
    contentUnavailableConfiguration = loading
    spinner.startAnimating()
    let sessionId = sessionId
    let path = path
    let runtime = runtime
    loadTask = Task { [weak self] in
      do {
        let json = try await FilePreview.read(sessionId: sessionId, path: path, runtime: runtime)
        try Task.checkCancellation()
        guard let self else { return }
        self.show(json)
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, let self else { return }
        self.fail(LodyStrings.text("native.file.error.offline"))
      }
    }
  }

  private func show(_ json: String) {
    guard let data = json.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      fail(LodyStrings.text("native.file.error.read"))
      return
    }
    if object["status"] as? String != "ok" {
      let code = object["code"] as? String ?? ""
      let keys = [
        "too_large": "native.file.error.tooLarge",
        "file_not_found": "native.file.error.notFound",
        "permission_denied": "native.file.error.permissionDenied",
        "path_not_allowed": "native.file.error.pathNotAllowed",
        "decode_error": "native.file.error.decode",
      ]
      fail(LodyStrings.text(keys[code] ?? "native.file.error.read"))
      return
    }
    guard let handle = object["handle"] as? String else {
      fail(LodyStrings.text("native.file.error.read"))
      return
    }
    do {
      previewURL = try ContentPreview.prepare(handle: handle, directory: directory)
    } catch {
      fail(LodyStrings.text("native.file.error.stale"))
      return
    }
    spinner.stopAnimating()
    contentUnavailableConfiguration = nil
    reloadData()
  }

  private func fail(_ message: String) {
    var failed = UIContentUnavailableConfiguration.empty()
    failed.background.backgroundColor = .systemBackground
    failed.image = UIImage(systemName: "doc.badge.ellipsis")
    failed.text = (path as NSString).lastPathComponent
    failed.secondaryText = message
    failed.button.title = LodyStrings.text("native.file.retry")
    failed.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.load() }
    failed.secondaryButton.title = LodyStrings.text("native.close")
    failed.secondaryButtonProperties.primaryAction = UIAction { [weak self] _ in self?.dismiss(animated: true) }
    spinner.stopAnimating()
    contentUnavailableConfiguration = failed
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    loadTask?.cancel()
    try? FileManager.default.removeItem(at: directory)
    onClose?()
    onClose = nil
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed {
      loadTask?.cancel()
      onClose?()
      onClose = nil
    }
  }

  deinit {
    loadTask?.cancel()
    try? FileManager.default.removeItem(at: directory)
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { previewURL == nil ? 0 : 1 }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    previewURL! as NSURL
  }
}

@MainActor
final class FilePreviewController: UIViewController {
  private let sessionId: String
  private let path: String
  private let line: Int
  private let runtime: DataRuntime
  private var onClose: (() -> Void)?
  private var loadTask: Task<Void, Never>?
  private var handle = ""
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let errorLabel = UILabel()
  private let retry = UIButton(type: .system)
  private let code = LodyCodeView()
  private var showingSource: Bool
  private var markdown = false

  static func present(
    sessionId: String,
    path: String,
    line: Int,
    runtime: DataRuntime,
    from controller: UIViewController
  ) async {
    await withCheckedContinuation { continuation in
      let preview = FilePreviewController(sessionId: sessionId, path: path, line: line, runtime: runtime)
      preview.onClose = { continuation.resume() }
      preview.title = (path as NSString).lastPathComponent
      let navigation = UINavigationController(rootViewController: preview)
      navigation.modalPresentationStyle = .pageSheet
      if let sheet = navigation.sheetPresentationController {
        sheet.detents = [.large()]
        sheet.prefersGrabberVisible = true
      }
      var host = controller
      while let presented = host.presentedViewController { host = presented }
      host.present(navigation, animated: true)
    }
  }

  private init(sessionId: String, path: String, line: Int, runtime: DataRuntime) {
    self.sessionId = sessionId
    self.path = path
    self.line = line
    self.runtime = runtime
    showingSource = line > 0
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .lodyBackground
    let back = UIButton(type: .system)
    back.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
    back.accessibilityIdentifier = "file-back"
    back.accessibilityLabel = "Back"
    back.addAction(UIAction { [weak self] _ in self?.goBack() }, for: .touchUpInside)
    back.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
    navigationItem.hidesBackButton = true
    navigationItem.leftBarButtonItem = UIBarButtonItem(customView: back)
    spinner.color = .secondaryLabel
    spinner.accessibilityIdentifier = "file-loading"
    spinner.accessibilityLabel = LodyStrings.text("native.file.reading")
    spinner.hidesWhenStopped = true
    errorLabel.font = .preferredFont(forTextStyle: .footnote)
    errorLabel.textColor = .secondaryLabel
    errorLabel.textAlignment = .center
    errorLabel.numberOfLines = 0
    retry.setTitle(LodyStrings.text("native.file.retry"), for: .normal)
    retry.addAction(UIAction { [weak self] _ in self?.load() }, for: .touchUpInside)
    code.onOpenFile = { [weak self] href, line in
      guard let self else { return }
      Task {
        await FilePreview.open(
          sessionId: self.sessionId,
          path: FilePreview.resolve(href: href, from: self.path),
          line: line,
          runtime: self.runtime,
          from: self
        )
      }
    }
    code.onRenderFail = { [weak self] in
      self?.showError(LodyStrings.text("native.file.error.stale"))
    }
    view.addSubview(spinner)
    view.addSubview(errorLabel)
    view.addSubview(retry)
    view.addSubview(code)
    load()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    spinner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    let inset = view.safeAreaInsets
    errorLabel.frame = CGRect(x: 24, y: inset.top + 80, width: view.bounds.width - 48, height: 80)
    retry.frame = CGRect(x: 24, y: errorLabel.frame.maxY + 12, width: view.bounds.width - 48, height: 44)
    code.frame = view.bounds
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isBeingDismissed { finish() }
  }

  override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    if parent == nil, presentingViewController == nil { finish() }
  }

  private func goBack() {
    if let navigation = navigationController, navigation.viewControllers.count > 1 {
      navigation.popViewController(animated: true)
      return
    }
    let presenter = presentingViewController ?? navigationController?.presentingViewController
    if let presenter {
      presenter.dismiss(animated: true) { [weak self] in self?.finish() }
      return
    }
    dismiss(animated: true) { [weak self] in self?.finish() }
  }

  private func finish() {
    loadTask?.cancel()
    onClose?()
    onClose = nil
  }

  private func load() {
    loadTask?.cancel()
    showLoading()
    let sessionId = sessionId
    let path = path
    let runtime = runtime
    loadTask = Task { [weak self] in
      do {
        let json = try await FilePreview.read(sessionId: sessionId, path: path, runtime: runtime)
        try Task.checkCancellation()
        guard let self else { return }
        self.apply(json)
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled, let self else { return }
        self.showError(LodyStrings.text("native.file.error.offline"))
      }
    }
  }

  private func apply(_ json: String) {
    guard let data = json.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      showError(LodyStrings.text("native.file.error.read"))
      return
    }
    if object["status"] as? String != "ok" {
      let code = object["code"] as? String ?? ""
      let keys = [
        "too_large": "native.file.error.tooLarge",
        "file_not_found": "native.file.error.notFound",
        "permission_denied": "native.file.error.permissionDenied",
        "path_not_allowed": "native.file.error.pathNotAllowed",
        "decode_error": "native.file.error.decode",
      ]
      showError(LodyStrings.text(keys[code] ?? "native.file.error.read"))
      return
    }
    guard let handle = object["handle"] as? String, !handle.isEmpty else {
      showError(LodyStrings.text("native.file.error.read"))
      return
    }
    self.handle = handle
    markdown = ["md", "markdown", "mdx"].contains((path as NSString).pathExtension.lowercased())
    showCode()
  }

  private func showLoading() {
    spinner.startAnimating()
    errorLabel.isHidden = true
    retry.isHidden = true
    code.isHidden = true
    navigationItem.rightBarButtonItem = nil
  }

  private func showError(_ message: String) {
    spinner.stopAnimating()
    errorLabel.text = message
    errorLabel.isHidden = false
    retry.isHidden = false
    code.isHidden = true
    navigationItem.rightBarButtonItem = nil
  }

  private func showCode() {
    spinner.stopAnimating()
    errorLabel.isHidden = true
    retry.isHidden = true
    code.isHidden = false
    code.setPath(path)
    code.setLine(line)
    code.setMarkdown(markdown && !showingSource)
    code.setHandle(handle)
    updateToggle()
  }

  private func updateToggle() {
    guard markdown else {
      navigationItem.rightBarButtonItem = nil
      return
    }
    let title = LodyStrings.text(showingSource ? "native.file.preview" : "native.file.source")
    navigationItem.rightBarButtonItem = UIBarButtonItem(title: title, primaryAction: UIAction { [weak self] _ in
      guard let self else { return }
      self.showingSource.toggle()
      self.code.setMarkdown(self.markdown && !self.showingSource)
      self.updateToggle()
    })
    navigationItem.rightBarButtonItem?.accessibilityLabel = title
  }
}
