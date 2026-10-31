import UIKit

@MainActor
final class MermaidDiagramView: UIView, MermaidBlock, UIContextMenuInteractionDelegate {
  private static let images: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 32
    cache.totalCostLimit = 96 * 1024 * 1024
    return cache
  }()

  let source: String
  private let svg: String
  private let size: CGSize
  private let imageView = UIImageView()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private var task: Task<Void, Never>?
  private var colors = (background: "", foreground: "")
  private(set) var state = "loading"
  private(set) var imageKey = ""

  init(source: String, svg: String, size: CGSize, traits: UITraitCollection) {
    self.source = source
    self.svg = svg
    self.size = size
    super.init(frame: .zero)
    layer.cornerRadius = 12
    layer.cornerCurve = .continuous
    clipsToBounds = true
    imageView.contentMode = .scaleAspectFit
    spinner.color = .secondaryLabel
    addSubview(imageView)
    addSubview(spinner)
    accessibilityIdentifier = "markdown-mermaid"
    accessibilityLabel = "Mermaid\n" + source
    accessibilityTraits = [.image, .button]
    isAccessibilityElement = true
    accessibilityCustomActions = [MarkdownMermaid.copyAction(source, name: String(localized: "native.chat.copy", bundle: .lody))]
    addInteraction(UIContextMenuInteraction(delegate: self))
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openPreview)))
    registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: MermaidDiagramView, _) in
      view.render(view.traitCollection)
    }
    render(traits)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  isolated deinit {
    task?.cancel()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    imageView.frame = bounds
    spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
    MarkdownMermaid.record(self)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil { render(traitCollection) }
    MarkdownMermaid.record(self)
  }

  private func render(_ traits: UITraitCollection) {
    let background = MermaidRaster.hex(UIColor.lodyBackground.resolvedColor(with: traits))
    let foreground = MermaidRaster.hex(UIColor.label.resolvedColor(with: traits))
    let scale = traits.displayScale > 0 ? traits.displayScale : 3
    let key = "\(background)\(foreground)@\(scale)"
    guard key != imageKey else { return }
    imageKey = key
    colors = (background, foreground)
    task?.cancel()
    let cacheKey = (key + "\n" + source) as NSString
    if let image = Self.images.object(forKey: cacheKey) {
      show(image)
      return
    }
    state = "loading"
    imageView.image = nil
    backgroundColor = .lodyInset
    spinner.startAnimating()
    let svg = svg, size = size
    task = Task { [weak self] in
      let result = await Task.detached(priority: .userInitiated) {
        Result { try MermaidRaster.image(svg: svg, size: size, background: background, foreground: foreground, scale: scale) }
      }.value
      guard let self, !Task.isCancelled, self.imageKey == key else { return }
      switch result {
      case .success(let image):
        Self.images.setObject(image, forKey: cacheKey, cost: Int(size.width * size.height * scale * scale * 4))
        self.show(image)
      case .failure:
        self.state = "failed"
        self.spinner.stopAnimating()
        self.imageView.contentMode = .center
        self.imageView.tintColor = .secondaryLabel
        self.imageView.image = UIImage(systemName: "exclamationmark.triangle")
        MarkdownMermaid.record(self)
      }
    }
  }

  private func show(_ image: UIImage) {
    state = "rendered"
    spinner.stopAnimating()
    backgroundColor = .clear
    imageView.contentMode = .scaleAspectFit
    imageView.image = image
    MarkdownMermaid.record(self)
  }

  override func accessibilityActivate() -> Bool {
    openPreview()
    return true
  }

  @objc private func openPreview() {
    guard state == "rendered", let image = imageView.image, let controller = owningController(),
      let preview = ImagePreviewController.present(from: controller, image: image, name: "Mermaid", url: nil, sourceView: self) else { return }
    let svg = svg, size = size, colors = colors
    let scale = (traitCollection.displayScale > 0 ? traitCollection.displayScale : 3) * ChatImagePreviewGeometry.maxScale
    Task { [weak preview] in
      let sharp = await Task.detached(priority: .userInitiated) {
        try? MermaidRaster.image(svg: svg, size: size, background: colors.background, foreground: colors.foreground, scale: scale)
      }.value
      guard let sharp, let preview else { return }
      preview.updateCurrentImage(sharp)
    }
  }

  private func owningController() -> UIViewController? {
    var responder = next
    while let current = responder {
      if let controller = current as? UIViewController { return controller }
      responder = current.next
    }
    return nil
  }

  func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
    MarkdownMermaid.copyMenu(source)
  }
}

@MainActor
final class MermaidFailureView: UIView, MermaidBlock, UIContextMenuInteractionDelegate {
  private static let inset = UIEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
  private static let symbolWidth: CGFloat = 22
  private static var titleFont: UIFont { .preferredFont(forTextStyle: .subheadline).withWeight(.semibold) }
  private static var reasonFont: UIFont { .preferredFont(forTextStyle: .footnote) }
  private static var sourceFont: UIFont { UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .regular)) }

  let source: String
  let state = "failed"
  let imageKey = ""
  private let symbol = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
  private let title = UILabel()
  private let reason = UILabel()
  private let separator = UIView()
  private let code = UILabel()

  init(source: String, reason text: String) {
    self.source = source
    super.init(frame: .zero)
    backgroundColor = .lodyInset
    layer.cornerRadius = 12
    layer.cornerCurve = .continuous
    symbol.tintColor = .systemOrange
    symbol.contentMode = .scaleAspectFit
    symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: Self.reasonFont)
    title.font = Self.titleFont
    title.text = String(localized: "native.chat.mermaid.failed", bundle: .lody)
    reason.font = Self.reasonFont
    reason.textColor = .secondaryLabel
    reason.numberOfLines = 0
    reason.text = text
    reason.isHidden = text.isEmpty
    separator.backgroundColor = .separator
    code.font = Self.sourceFont
    code.numberOfLines = 0
    code.text = Self.display(source)
    [symbol, title, reason, separator, code].forEach(addSubview)
    accessibilityIdentifier = "markdown-mermaid-failed"
    accessibilityLabel = [title.text ?? "", text, source].filter { !$0.isEmpty }.joined(separator: "\n")
    isAccessibilityElement = true
    accessibilityCustomActions = [MarkdownMermaid.copyAction(source, name: String(localized: "native.chat.copy", bundle: .lody))]
    addInteraction(UIContextMenuInteraction(delegate: self))
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private struct Frames {
    var symbol: CGRect
    var title: CGRect
    var reason: CGRect
    var separator: CGRect
    var code: CGRect
  }

  private static func frames(width: CGFloat, reason: String, source: String) -> Frames {
    func height(_ text: String, _ font: UIFont, _ width: CGFloat) -> CGFloat {
      guard !text.isEmpty else { return 0 }
      return ceil((text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil).height)
    }
    let content = max(1, width - inset.left - inset.right)
    let titleHeight = ceil(titleFont.lineHeight)
    let symbol = CGRect(x: inset.left, y: inset.top, width: symbolWidth - 6, height: titleHeight)
    let title = CGRect(x: inset.left + symbolWidth, y: inset.top, width: content - symbolWidth, height: titleHeight)
    let reasonHeight = height(reason, reasonFont, content)
    let reasonFrame = CGRect(x: inset.left, y: title.maxY + (reasonHeight > 0 ? 2 : 0), width: content, height: reasonHeight)
    let separator = CGRect(x: inset.left, y: reasonFrame.maxY + 10, width: content, height: 1 / max(1, UITraitCollection.current.displayScale))
    let code = CGRect(x: inset.left, y: separator.maxY + 10, width: content, height: height(display(source), sourceFont, content))
    return Frames(symbol: symbol, title: title, reason: reasonFrame, separator: separator, code: code)
  }

  private static func display(_ source: String) -> String {
    source.trimmingCharacters(in: .newlines)
  }

  static func height(width: CGFloat, reason: String, source: String) -> CGFloat {
    ceil(frames(width: width, reason: reason, source: source).code.maxY + inset.bottom)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let frames = Self.frames(width: bounds.width, reason: reason.text ?? "", source: source)
    symbol.frame = frames.symbol
    title.frame = frames.title
    reason.frame = frames.reason
    separator.frame = frames.separator
    code.frame = frames.code
    MarkdownMermaid.record(self)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    MarkdownMermaid.record(self)
  }

  func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
    MarkdownMermaid.copyMenu(source)
  }
}
