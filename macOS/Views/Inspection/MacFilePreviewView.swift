import AppKit
import Quartz
import LodyData

@MainActor
final class MacFilePreviewView: NSView, @preconcurrency QLPreviewPanelDataSource {
  let target: MacInspectionTarget
  let content: MacInspectionContent
  private weak var model: MacInspectionModel?
  private let scroll = NSScrollView()
  private let text = NSTextView()
  private let toolbar = NSStackView()
  private let image = NSImageView()
  private let zoom = NSPopUpButton()
  private var picture: NSImage?
  private var quick: QLPreviewView?
  private var temporary: URL?
  private var originalURL: URL?
  private var observer: NSObjectProtocol?
  private var restoring = false
  private var mode = ""

  init(target: MacInspectionTarget, content: MacInspectionContent, model: MacInspectionModel) {
    self.target = target; self.content = content; self.model = model
    super.init(frame: .zero)
    setAccessibilityIdentifier("inspection-preview")
    let path = NSTextField(labelWithString: target.path)
    path.font = .systemFont(ofSize: 12, weight: .medium); path.lineBreakMode = .byTruncatingMiddle; path.toolTip = target.path
    path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    toolbar.setViews([path], in: .leading)
    toolbar.spacing = 6; toolbar.edgeInsets = .init(top: 7, left: 10, bottom: 7, right: 10)
    let refresh = MacInspectionUI.button(MacInspectionUI.text("mac.inspection.refresh"), "inspection-refresh") { [weak model] in model?.refresh() }
    toolbar.addArrangedSubview(refresh)
    for child in [toolbar, scroll] { child.translatesAutoresizingMaskIntoConstraints = false; addSubview(child) }
    NSLayoutConstraint.activate([
      toolbar.topAnchor.constraint(equalTo: topAnchor), toolbar.leadingAnchor.constraint(equalTo: leadingAnchor), toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
      scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    switch content {
    case .stored(let handle):
      if let stored = ContentStore.shared.get(handle) {
        if ["text", "markdown"].contains(stored.kind), let value = String(data: stored.data, encoding: .utf8), stored.data.count <= 1024 * 1024 { showText(value) }
        else if let picture = NSImage(data: stored.data) { showImage(picture) }
        else { showStoredPreview(stored) }
      } else { showMessage(MacInspectionUI.text("mac.inspection.evicted")) }
    case .url(let url):
      originalURL = url
      if let picture = NSImage(contentsOf: url), !["pdf", "eps"].contains(url.pathExtension.lowercased()) { showImage(picture) }
      else if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1024 * 1024,
              let value = try? String(contentsOf: url, encoding: .utf8), !value.contains("\0") { showText(value) }
      else { showQuickLook(url) }
    }
    scroll.contentView.postsBoundsChangedNotifications = true
    observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.saveReading() }
    }
  }
  required init?(coder: NSCoder) { nil }
  isolated deinit {
    if let observer { NotificationCenter.default.removeObserver(observer) }
    quick?.close()
    if let temporary { try? FileManager.default.removeItem(at: temporary) }
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil { restoreReading() }
  }
  override func layout() {
    super.layout()
    if mode == "image", zoom.indexOfSelectedItem == 0 { layoutImage() }
    if mode == "text", let tab = model?.state.tabs.first(where: { $0.target == target }), tab.wrap { setWrap(true) }
  }

  private func showText(_ value: String) {
    mode = "text"
    text.isEditable = false; text.isSelectable = true; text.isRichText = false
    text.isAutomaticLinkDetectionEnabled = false
    text.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
    text.textColor = .labelColor; text.backgroundColor = .textBackgroundColor
    text.textContainerInset = .init(width: 10, height: 12)
    text.usesFindBar = true; text.isIncrementalSearchingEnabled = true
    text.setAccessibilityIdentifier("inspection-text")
    text.textStorage?.setAttributedString(MacInspectionSyntax.code(value))
    scroll.documentView = text
    let wrap = MacInspectionUI.button(MacInspectionUI.text("mac.inspection.wrap"), "inspection-wrap") { [weak self] in
      guard let self else { return }
      let old = self.model?.state.tabs.first(where: { $0.target == self.target })?.wrap ?? false
      self.model?.state.updateReading(self.target, x: self.scroll.contentView.bounds.minX, y: self.scroll.contentView.bounds.minY, wrap: !old)
      self.setWrap(!old)
    }
    toolbar.addArrangedSubview(wrap)
    toolbar.addArrangedSubview(MacInspectionUI.button(MacInspectionUI.text("mac.inspection.find"), "inspection-find") { [weak self] in self?.find() })
    let ruler = MacInspectionLineRuler(text: text)
    scroll.verticalRulerView = ruler; scroll.hasVerticalRuler = true; scroll.rulersVisible = true
    setWrap(model?.state.tabs.first(where: { $0.target == target })?.wrap ?? false)
  }

  private func setWrap(_ wrap: Bool) {
    guard let container = text.textContainer else { return }
    text.isVerticallyResizable = true; text.isHorizontallyResizable = !wrap
    text.autoresizingMask = wrap ? [.width] : []
    container.widthTracksTextView = wrap
    let width = max(280, scroll.contentSize.width)
    container.containerSize = .init(width: wrap ? width : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    text.setFrameSize(.init(width: width, height: max(100, scroll.contentSize.height)))
    if let manager = text.layoutManager {
      manager.ensureLayout(for: container)
      let used = manager.usedRect(for: container)
      text.setFrameSize(.init(width: wrap ? width : max(width, used.width + 24), height: max(scroll.contentSize.height, used.height + 24)))
    }
  }

  func find() {
    guard mode == "text" else { return }
    window?.makeFirstResponder(text)
    let sender = NSMenuItem(); sender.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
    text.performFindPanelAction(sender)
  }

  private func showImage(_ picture: NSImage) {
    mode = "image"; self.picture = picture
    image.image = picture; image.imageScaling = .scaleAxesIndependently
    image.setAccessibilityIdentifier("inspection-image")
    scroll.documentView = image
    zoom.addItems(withTitles: [MacInspectionUI.text("mac.inspection.fit"), "100%", "200%"])
    zoom.target = self; zoom.action = #selector(changeZoom)
    zoom.setAccessibilityLabel(MacInspectionUI.text("mac.inspection.imageZoom")); zoom.setAccessibilityIdentifier("inspection-image-zoom")
    toolbar.addArrangedSubview(zoom)
    layoutImage()
  }
  @objc private func changeZoom() { layoutImage() }
  private func layoutImage() {
    guard let picture else { return }
    let size = picture.size
    var scale = 1.0
    if zoom.indexOfSelectedItem == 0 { scale = min(1, max(1, scroll.contentSize.width - 32) / max(1, size.width), max(1, scroll.contentSize.height - 32) / max(1, size.height)) }
    if zoom.indexOfSelectedItem == 2 { scale = 2 }
    image.frame = .init(x: 0, y: 0, width: max(1, size.width * scale), height: max(1, size.height * scale))
  }

  private func showStoredPreview(_ stored: StoredContent) {
    do {
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lody-inspection-" + UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      temporary = directory
      let url = directory.appendingPathComponent((stored.path as NSString).lastPathComponent)
      try stored.data.write(to: url); originalURL = url; showQuickLook(url)
    } catch { showMessage(error.localizedDescription) }
  }
  private func showQuickLook(_ url: URL) {
    mode = "quick"
    if let preview = QLPreviewView(frame: .zero, style: .normal) {
      quick = preview; preview.previewItem = url as NSURL
      preview.autostarts = false
      preview.translatesAutoresizingMaskIntoConstraints = false
      addSubview(preview)
      scroll.isHidden = true
      NSLayoutConstraint.activate([preview.topAnchor.constraint(equalTo: toolbar.bottomAnchor), preview.leadingAnchor.constraint(equalTo: leadingAnchor), preview.trailingAnchor.constraint(equalTo: trailingAnchor), preview.bottomAnchor.constraint(equalTo: bottomAnchor)])
    }
    toolbar.addArrangedSubview(MacInspectionUI.button(MacInspectionUI.text("mac.inspection.quickLook"), "inspection-quicklook") { [weak self] in
      guard let self, let url = self.originalURL else { return }
      guard let panel = QLPreviewPanel.shared() else { return }
      self.window?.makeFirstResponder(self)
      panel.updateController(); panel.reloadData(); panel.makeKeyAndOrderFront(nil)
    })
  }
  private func showMessage(_ value: String) {
    let field = NSTextField(wrappingLabelWithString: value); scroll.documentView = field
  }
  func saveReading() {
    guard !restoring, let model else { return }
    let wrap = model.state.tabs.first(where: { $0.target == target })?.wrap ?? false
    model.state.updateReading(target, x: scroll.contentView.bounds.minX, y: scroll.contentView.bounds.minY, wrap: wrap)
    scroll.verticalRulerView?.needsDisplay = true
  }
  private func restoreReading() {
    guard let tab = model?.state.tabs.first(where: { $0.target == target }) else { return }
    restoring = true; layoutSubtreeIfNeeded()
    scroll.contentView.scroll(to: .init(x: tab.scrollX, y: tab.scrollY)); scroll.reflectScrolledClipView(scroll.contentView)
    restoring = false
  }
  override var acceptsFirstResponder: Bool { true }
  override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { MainActor.assumeIsolated { originalURL != nil } }
  override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { MainActor.assumeIsolated { panel.dataSource = self } }
  override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { MainActor.assumeIsolated { panel.dataSource = nil } }
  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { originalURL == nil ? 0 : 1 }
  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { originalURL as NSURL? }
}

@MainActor
private final class MacInspectionLineRuler: NSRulerView {
  private weak var text: NSTextView?
  private let starts: [Int]
  init(text: NSTextView) {
    self.text = text
    let value = text.string as NSString
    var starts = [0]
    for index in 0..<value.length where value.character(at: index) == 10 { starts.append(index + 1) }
    self.starts = starts
    super.init(scrollView: text.enclosingScrollView, orientation: .verticalRuler)
    clientView = text; ruleThickness = 44
  }
  required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override var isFlipped: Bool { true }
  override func drawHashMarksAndLabels(in rect: NSRect) {
    guard let text, let layout = text.layoutManager, let container = text.textContainer else { return }
    NSColor.windowBackgroundColor.setFill(); rect.fill()
    var visible = text.visibleRect; visible.origin.y -= text.textContainerOrigin.y
    let range = layout.glyphRange(forBoundingRect: visible, in: container)
    layout.enumerateLineFragments(forGlyphRange: range) { line, _, _, glyphs, _ in
      let character = layout.characterIndexForGlyph(at: glyphs.location)
      var lower = 0, upper = self.starts.count
      while lower < upper { let mid = (lower + upper) / 2; if self.starts[mid] <= character { lower = mid + 1 } else { upper = mid } }
      let value = String(lower) as NSString
      let point = self.convert(NSPoint(x: 0, y: line.minY + text.textContainerOrigin.y), from: text)
      value.draw(at: .init(x: 6, y: point.y), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
    }
  }
}
