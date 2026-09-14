import UIKit

/// A separate row keeps image geometry out of text measurement and message bubbles.
final class ChatImageCell: UICollectionViewCell {
  private var photo = UIImageView()
  var compact = false
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let failure = UILabel()
  private var image: ChatImage?
  private var workspace = ""
  private var session = ""
  private var handoffEntryID: String?
  private var requestURL: URL?
  private var requestID = UUID()
  private var task: URLSessionDataTask?

  override init(frame: CGRect) {
    super.init(frame: frame)
    photo.contentMode = .scaleAspectFit
    photo.backgroundColor = .lodyInset
    photo.layer.cornerRadius = 16
    photo.layer.cornerCurve = .continuous
    photo.clipsToBounds = true
    photo.layer.borderWidth = 0.5
    registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (cell: ChatImageCell, _) in cell.setNeedsLayout() }
    failure.text = LodyStrings.text("native.chat.image.failed")
    failure.font = .preferredFont(forTextStyle: .caption1)
    failure.textColor = .secondaryLabel
    failure.textAlignment = .center
    failure.isHidden = true
    contentView.addSubview(photo)
    photo.addSubview(spinner)
    photo.addSubview(failure)
    isAccessibilityElement = true
    accessibilityTraits = [.image, .button]
    accessibilityHint = LodyStrings.text("native.chat.image.openPreview")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  static func size(_ image: ChatImage, width: CGFloat) -> CGSize {
    let ratio = max(0.1, min(10, (image.width ?? 4) / (image.height ?? 3)))
    let maximum = min(240, width * 0.84)
    return ratio >= 1 ? CGSize(width: maximum, height: maximum / ratio) : CGSize(width: maximum * ratio, height: maximum)
  }
  func configure(_ row: ChatRow, workspace: String, session: String) {
    guard let image = row.image else { return }
    let hadLocalImage = requestURL?.isFileURL == true && handoffEntryID == row.entryID
    self.image = image
    self.workspace = workspace
    self.session = session
    if row.localImageURI != nil { handoffEntryID = row.entryID }
    else if !hadLocalImage { handoffEntryID = nil }
    accessibilityIdentifier = row.id
    accessibilityLabel = LodyStrings.text("native.chat.image.label", ["name": image.fileName])
    setNeedsLayout()
    if let uri = row.localImageURI, let url = URL(string: uri), url.isFileURL {
      if requestURL == url, photo.image != nil { return }
      task?.cancel(); task = nil; requestURL = url; requestID = UUID()
      photo.image = ChatAttachment.thumbnail(url)
      spinner.stopAnimating(); failure.isHidden = photo.image != nil
      return
    }
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--ui-verify"), image.id == "ui-verify-image" {
      task?.cancel(); task = nil; requestURL = nil; requestID = UUID()
      photo.image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400)).image { context in
        UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        UIColor.white.setFill(); context.fill(CGRect(x: 100, y: 100, width: 400, height: 200))
      }
      spinner.stopAnimating(); failure.isHidden = true
      return
    }
    #endif
    guard !workspace.isEmpty, !session.isEmpty, !image.id.isEmpty else {
      task?.cancel(); task = nil; requestURL = nil; requestID = UUID()
      photo.image = nil; spinner.stopAnimating(); failure.isHidden = false
      return
    }
    let storage = image.storageSessionId ?? session
    let thumbnail = SessionAttachments.imageThumbnailURL(
      workspace: workspace, session: storage, imageId: image.id, width: 768
    )
    let original = SessionAttachments.imageDownloadURL(
      workspace: workspace, session: storage, imageId: image.id
    )
    if requestURL == thumbnail && (task != nil || photo.image != nil) { return }
    if requestURL == original && (task != nil || photo.image != nil) { return }
    let requestID = UUID(); self.requestID = requestID
    task?.cancel(); requestURL = thumbnail
    if !hadLocalImage { photo.image = nil }
    failure.isHidden = true
    guard let token = try? AuthKeychain.read() else { failure.isHidden = false; return }
    fetch(thumbnail, fallback: original, requestID: requestID, token: token)
  }

  private func fetch(_ url: URL, fallback: URL?, requestID: UUID, token: String) {
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("image/*,*/*", forHTTPHeaderField: "Accept")
    spinner.startAnimating()
    task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
      let valid = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
      let decoded = valid ? data.flatMap(UIImage.init(data:)) : nil
      DispatchQueue.main.async {
        guard let self, self.requestID == requestID else { return }
        if let decoded {
          self.task = nil
          self.spinner.stopAnimating()
          self.photo.image = decoded
          self.failure.isHidden = true
          return
        }
        if let fallback {
          self.requestURL = fallback
          self.fetch(fallback, fallback: nil, requestID: requestID, token: token)
          return
        }
        self.task = nil
        self.spinner.stopAnimating()
        self.failure.isHidden = self.photo.image != nil
      }
    }
    task?.resume()
  }
  override func prepareForReuse() {
    super.prepareForReuse()
    task?.cancel(); task = nil; requestURL = nil; requestID = UUID()
    photo.image = nil; spinner.stopAnimating(); failure.isHidden = true
  }

  func presentPreview(from controller: UIViewController) {
    guard let image, controller.presentedViewController == nil else { return }
    #if DEBUG
    let fixture = ProcessInfo.processInfo.arguments.contains("--ui-verify") && image.id == "ui-verify-image"
    #else
    let fixture = false
    #endif
    guard fixture || requestURL != nil || photo.image != nil else { return }
    let previewURL: URL?
    if fixture || requestURL?.isFileURL == true {
      previewURL = nil
    } else if !workspace.isEmpty, !session.isEmpty, !image.id.isEmpty {
      previewURL = SessionAttachments.imageDownloadURL(
        workspace: workspace,
        session: image.storageSessionId ?? session,
        imageId: image.id
      )
    } else {
      previewURL = nil
    }
    let preview = ChatImagePreview(image: photo.image, name: image.fileName, url: previewURL)
    let presentedURL = requestURL
    preview.preferredTransition = .zoom { [weak self] _ in
      guard let self, self.window != nil else { return nil }
      if let presentedURL, self.requestURL != presentedURL { return nil }
      return self.photo
    }
    controller.present(preview, animated: true)
  }
  override func layoutSubviews() {
    super.layoutSubviews()
    guard let image else { return }
    photo.layer.borderColor = UIColor.separator.resolvedColor(with: traitCollection).cgColor
    let size = compact ? contentView.bounds.size : Self.size(image, width: contentView.bounds.width)
    photo.frame = CGRect(x: 0, y: compact ? 0 : 6, width: size.width, height: size.height)
    spinner.center = CGPoint(x: size.width / 2, y: size.height / 2)
    failure.frame = photo.bounds.insetBy(dx: 4, dy: 4)
  }
}

/// UIKit owns the thumbnail zoom transition and interactive dismissal.
final class ChatImagePreview: UIViewController, UIScrollViewDelegate {
  private let scroll = UIScrollView()
  private let photo = UIImageView()
  private let spinner = UIActivityIndicatorView(style: .large)
  private let retry = UIButton(type: .system)
  private let url: URL?
  private var task: URLSessionDataTask?
  private var viewport = CGSize.zero

  init(image: UIImage?, name: String, url: URL?) {
    self.url = url
    super.init(nibName: nil, bundle: nil)
    photo.image = image
    photo.accessibilityLabel = name
    modalPresentationStyle = .fullScreen
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  deinit { task?.cancel() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    view.accessibilityIdentifier = "chat-image-preview"
    scroll.delegate = self
    scroll.minimumZoomScale = 1
    scroll.maximumZoomScale = 4
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.showsHorizontalScrollIndicator = false
    scroll.showsVerticalScrollIndicator = false
    view.addSubview(scroll)
    photo.contentMode = .scaleAspectFit
    photo.isAccessibilityElement = true
    photo.accessibilityTraits = .image
    scroll.addSubview(photo)
    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(zoom(_:)))
    doubleTap.numberOfTapsRequired = 2
    scroll.addGestureRecognizer(doubleTap)
    let close = UIButton(type: .system)
    var config = UIButton.Configuration.filled()
    config.image = UIImage(systemName: "xmark")
    config.baseForegroundColor = .white
    config.baseBackgroundColor = UIColor(white: 0.18, alpha: 0.9)
    config.cornerStyle = .capsule
    close.configuration = config
    close.accessibilityLabel = LodyStrings.text("native.chat.image.closePreview")
    close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)
    close.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(close)
    NSLayoutConstraint.activate([
      close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      close.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
      close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44),
    ])
    spinner.color = .white
    view.addSubview(spinner)
    retry.setTitle(LodyStrings.text("native.chat.image.retry"), for: .normal)
    retry.tintColor = .white
    retry.backgroundColor = UIColor(white: 0.15, alpha: 0.9)
    retry.layer.cornerRadius = 12
    retry.addAction(UIAction { [weak self] _ in self?.loadImage() }, for: .touchUpInside)
    view.addSubview(retry)
    loadImage()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    if viewport != view.bounds.size {
      viewport = view.bounds.size
      scroll.frame = view.bounds
      fitImage()
    }
    spinner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    retry.frame = CGRect(x: 24, y: view.bounds.height - view.safeAreaInsets.bottom - 60, width: view.bounds.width - 48, height: 44)
  }

  private func fitImage() {
    scroll.zoomScale = 1
    let size = photo.image?.size ?? CGSize(width: 1, height: 1)
    let scale = min(scroll.bounds.width / max(size.width, 1), scroll.bounds.height / max(size.height, 1))
    photo.frame = CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))
    scroll.contentSize = photo.frame.size
    scrollViewDidZoom(scroll)
  }

  private func loadImage() {
    retry.isHidden = true
    guard let url else { return }
    guard let token = try? AuthKeychain.read() else { retry.isHidden = false; return }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("image/*,*/*", forHTTPHeaderField: "Accept")
    spinner.startAnimating()
    task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
      let valid = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
      let image = valid ? data.flatMap(UIImage.init(data:)) : nil
      DispatchQueue.main.async {
        guard let self else { return }
        self.spinner.stopAnimating()
        if let image {
          self.photo.image = image
          self.fitImage()
          self.retry.isHidden = true
          return
        }
        self.retry.isHidden = self.photo.image != nil
      }
    }
    task?.resume()
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }
  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    let x = max(0, (scroll.bounds.width - photo.frame.width) / 2)
    let y = max(0, (scroll.bounds.height - photo.frame.height) / 2)
    scroll.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    photo.accessibilityValue = "\(Int(scroll.zoomScale * 100))%"
  }
  override func accessibilityPerformEscape() -> Bool { dismiss(animated: true); return true }

  @objc private func zoom(_ gesture: UITapGestureRecognizer) {
    let animated = !UIAccessibility.isReduceMotionEnabled
    guard scroll.zoomScale <= 1.01 else { scroll.setZoomScale(1, animated: animated); return }
    let point = gesture.location(in: photo)
    let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
    scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: animated)
  }
}
