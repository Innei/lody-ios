import ExpoModulesCore
import UIKit

final class LodyMessageShareView: ExpoView, UIScrollViewDelegate {
  let onState = EventDispatcher()
  let onBlocks = EventDispatcher()
  private var selectedJSON = "null"
  private let scroll = UIScrollView()
  private let preview = UIImageView()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private var task: Task<Void, Never>?
  private var revision = 0
  private var contentJSON = ""
  private var file: URL?
  private var lastShareToken = 0
  private weak var scrollOwner: UIViewController?

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    scroll.delegate = self
    scroll.contentInsetAdjustmentBehavior = .automatic
    scroll.maximumZoomScale = 3
    LodyScrollEdges.navigation(scroll)
    addSubview(scroll)
    preview.contentMode = .scaleAspectFit
    preview.isAccessibilityElement = true
    preview.accessibilityIdentifier = "message-share-preview"
    preview.accessibilityLabel = LodyStrings.text("native.chat.message.preview")
    scroll.addSubview(preview)
    addSubview(spinner)
  }

  func setContent(_ json: String) {
    guard json != contentJSON else { return }
    contentJSON = json
    if window != nil { render() }
  }

  func setSelected(_ json: String) {
    guard json != selectedJSON else { return }
    selectedJSON = json
    if window != nil { render() }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      revision += 1
      task?.cancel()
      task = nil
      if let owner = scrollOwner { LodyScrollEdges.unbind(scroll, from: owner) }
      scrollOwner = nil
      removeFile()
      preview.image = nil
    } else if preview.image == nil, task == nil { render() }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if let owner = owningController() {
      scrollOwner = owner
      LodyScrollEdges.bind(scroll, to: owner)
    }
    let changed = scroll.bounds.size != bounds.size
    scroll.frame = bounds
    spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
    if changed { fitPreview() }
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? { preview }

  func share(_ token: Int) {
    guard token != lastShareToken else { return }
    lastShareToken = token
    guard token > 0, let file, let owner = owningController(), owner.presentedViewController == nil else { return }
    let activity = UIActivityViewController(activityItems: [file], applicationActivities: nil)
    activity.popoverPresentationController?.sourceView = self
    activity.popoverPresentationController?.sourceRect = CGRect(x: bounds.maxX - 44, y: safeAreaInsets.top, width: 44, height: 44)
    owner.present(activity, animated: true)
  }

  func retry(_ token: Int) { if token > 0 { render() } }

  private func render() {
    guard !contentJSON.isEmpty else { return }
    revision += 1
    let current = revision
    task?.cancel()
    removeFile()
    preview.image = nil
    spinner.startAnimating()
    onState(["state": "loading"])
    let json = contentJSON
    let selection = selectedJSON
    task = Task { @MainActor [weak self] in
      do {
        let content = try JSONDecoder().decode(ChatMessageShare.self, from: Data(json.utf8))
        let blocks = try ChatSharePaper.selections(content)
        let selected = try JSONDecoder().decode(Set<Int>?.self, from: Data(selection.utf8))
        guard let currentView = self, currentView.revision == current else { return }
        currentView.onBlocks(["blocks": blocks])
        if let selected, selected.isEmpty {
          currentView.spinner.stopAnimating()
          currentView.task = nil
          currentView.onState(["state": "empty"])
          return
        }
        let paper = try await ChatSharePaper.make(content, selected: selected)
        try Task.checkCancellation()
        guard let self, self.revision == current, self.window != nil else { return }
        // Mount the print view so UIKit resolves attachment views and traits.
        paper.frame.origin = CGPoint(x: -ChatMessageShare.width - 10, y: 0)
        self.addSubview(paper)
        defer { paper.removeFromSuperview() }
        @MainActor func layout(_ view: UIView) {
          view.setNeedsLayout()
          view.layoutIfNeeded()
          view.layer.displayIfNeeded()
          for child in view.subviews { layout(child) }
        }
        layout(paper)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.preferredRange = .standard
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: paper.bounds.size, format: format).image { output in
          paper.layer.render(in: output.cgContext)
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.92), let decoded = UIImage(data: jpeg) else { throw ChatSharePaper.Failure.render }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lody-message-share/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Lody.jpg")
        try jpeg.write(to: file, options: .atomic)
        self.file = file
        self.preview.image = decoded
        self.preview.accessibilityValue = "\(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale))"
        self.fitPreview()
        self.spinner.stopAnimating()
        self.task = nil
        self.onState(["state": "ready"])
      } catch {
        guard let self, self.revision == current, !Task.isCancelled else { return }
        self.spinner.stopAnimating()
        self.task = nil
        let key = (error as? ChatSharePaper.Failure) == .tooLarge ? "tooLarge" : "failed"
        self.onState(["state": "error", "retryable": key != "tooLarge", "message": LodyStrings.text("native.chat.message." + key)])
      }
    }
  }

  private func fitPreview() {
    guard let image = preview.image, bounds.width > 0 else { return }
    scroll.zoomScale = 1
    let width = min(bounds.width - 32, ChatMessageShare.width)
    preview.frame = CGRect(x: (bounds.width - width) / 2, y: 16, width: width, height: width * image.size.height / image.size.width)
    scroll.contentSize = CGSize(width: bounds.width, height: preview.frame.maxY + 16)
  }

  private func owningController() -> UIViewController? {
    var responder: UIResponder? = next
    while let current = responder {
      if let owner = current as? UIViewController { return owner }
      responder = current.next
    }
    return nil
  }

  private func removeFile() {
    if let file { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    file = nil
  }

  deinit {
    task?.cancel()
    if let file { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
  }
}
