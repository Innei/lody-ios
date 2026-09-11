import ExpoModulesCore
import MarkdownView
import UIKit

private let languages: [String: String] = [
  "ts": "typescript", "tsx": "typescript", "mts": "typescript", "cts": "typescript",
  "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript",
  "swift": "swift", "m": "objectivec", "h": "objectivec", "mm": "objectivec",
  "py": "python", "rb": "ruby", "go": "go", "rs": "rust", "java": "java", "kt": "kotlin",
  "c": "c", "cc": "cpp", "cpp": "cpp", "hpp": "cpp", "cs": "csharp", "php": "php",
  "sh": "bash", "bash": "bash", "zsh": "bash", "fish": "bash",
  "json": "json", "yml": "yaml", "yaml": "yaml", "toml": "ini", "ini": "ini",
  "md": "markdown", "mdx": "markdown", "html": "xml", "xml": "xml", "svg": "xml",
  "css": "css", "scss": "scss", "less": "less", "sql": "sql", "graphql": "graphql",
  "dockerfile": "dockerfile", "makefile": "makefile", "lua": "lua", "dart": "dart",
  "rb.erb": "erb", "vue": "xml", "podspec": "ruby", "gemfile": "ruby",
]

final class LodyCodeView: LodyAppearanceView, UITextViewDelegate {
  let onFail = EventDispatcher()
  let onFilePress = EventDispatcher()
  private let textView = UITextView()
  private let gutter = GutterView()
  private let documentScroll = UIScrollView()
  private let document = FileMarkdownView()
  private var renderMarkdown = false
  private var startLine = 0
  private var pendingLine = false
  private weak var scrollOwner: UIViewController?
  private var handle = ""
  private var path = ""
  private var lineStarts: [Int] = []
  private var renderScheduled = false

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    backgroundColor = .lodyBackground
    textView.isEditable = false
    textView.isSelectable = true
    textView.alwaysBounceVertical = true
    textView.showsHorizontalScrollIndicator = false
    textView.backgroundColor = .clear
    textView.contentInsetAdjustmentBehavior = .automatic
    textView.textContainer.lineFragmentPadding = 0
    textView.delegate = self
    documentScroll.alwaysBounceVertical = true
    documentScroll.contentInsetAdjustmentBehavior = .automatic
    documentScroll.accessibilityIdentifier = "file-document"
    document.accessibilityIdentifier = "file-document-content"
    document.accessibilityTraits = .staticText
    documentScroll.addSubview(document)
    document.trackedScrollView = documentScroll
    document.linkHandler = { [weak self] payload, _, _ in
      let href: String = switch payload {
      case .url(let url): url.absoluteString
      case .string(let value): value
      }
      if let target = ChatFileLink(href) {
        self?.onFilePress(["path": target.path, "line": target.line ?? 0])
      } else if let url = URL(string: href), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
        UIApplication.shared.open(url)
      }
    }
    addSubview(documentScroll)
    textView.accessibilityIdentifier = "file-source"
    addSubview(textView)
    gutter.textView = textView
    gutter.isUserInteractionEnabled = false
    addSubview(gutter)
  }

  func setMarkdown(_ value: Bool) { renderMarkdown = value; scheduleRender() }
  func setLine(_ value: Int) { startLine = value; scheduleRender() }
  func setHandle(_ value: String) { handle = value; scheduleRender() }
  func setPath(_ value: String) { path = value; scheduleRender() }

  private func scheduleRender() {
    guard !renderScheduled else { return }
    renderScheduled = true
    DispatchQueue.main.async { [weak self] in
      self?.renderScheduled = false
      self?.render()
    }
  }

  private func language() -> String? {
    let name = (path as NSString).lastPathComponent.lowercased()
    let ext = (name as NSString).pathExtension
    return languages[ext.isEmpty ? name : ext]
  }

  private func render() {
    guard !handle.isEmpty else { return }
    guard let content = ContentStore.shared.get(handle), let text = String(data: content.data, encoding: .utf8) else {
      onFail(["message": "content_expired"])
      return
    }
    var theme = ChatMarkdownTheme.make(traits: traitCollection, secondary: false)
    textView.isHidden = renderMarkdown
    gutter.isHidden = renderMarkdown
    documentScroll.isHidden = !renderMarkdown
    if renderMarkdown {
      let content = FileMarkdownView.content(MarkdownContent(markdown: text, theme: theme))
      document.setContentImmediately(content, theme: theme)
      document.accessibilityLabel = text
      document.isAccessibilityElement = true
      document.accessibilityCustomActions = document.fileActions(content)
      documentScroll.contentOffset = CGPoint(x: 0, y: -documentScroll.adjustedContentInset.top)
      attachScrollOwner()
      setNeedsLayout()
      return
    }
    theme.colors.code = .label
    // ponytail: highlightr runs on the main thread; above 256 KB the file shows plain text.
    let attributed: NSAttributedString
    if text.utf8.count <= 256 * 1024 {
      let map = CodeHighlighter.current.highlight(key: nil, content: text, language: language(), theme: theme)
      attributed = map.apply(to: text, with: theme)
    } else {
      attributed = CodeHighlighter.HighlightMap().apply(to: text, with: theme)
    }
    textView.attributedText = attributed
    lineStarts = [0]
    var index = 0
    for scalar in text.utf16 {
      index += 1
      if scalar == 0x0A { lineStarts.append(index) }
    }
    gutter.lineStarts = lineStarts
    gutter.font = theme.fonts.code
    gutter.width = Self.gutterWidth(lines: lineStarts.count, font: theme.fonts.code)
    textView.textContainerInset = UIEdgeInsets(top: 12, left: gutter.width + 8, bottom: 24, right: 16)
    textView.contentOffset = CGPoint(x: 0, y: -textView.adjustedContentInset.top)
    setNeedsLayout()
    gutter.setNeedsDisplay()
    pendingLine = startLine > 0 && startLine <= lineStarts.count
    attachScrollOwner()
  }

  private static func gutterWidth(lines: Int, font: UIFont) -> CGFloat {
    let digits = max(2, String(lines).count)
    let sample = String(repeating: "8", count: digits) as NSString
    return ceil(sample.size(withAttributes: [.font: font]).width) + 20
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    gutter.setNeedsDisplay()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    documentScroll.frame = bounds
    let width = max(1, bounds.width - 32)
    let height = document.boundingSize(for: width).height
    document.frame = CGRect(x: 16, y: 12, width: width, height: height)
    documentScroll.contentSize = CGSize(width: bounds.width, height: height + 36)
    textView.frame = bounds
    if pendingLine, !renderMarkdown, bounds.height > 0 {
      pendingLine = false
      textView.layoutIfNeeded()
      textView.scrollRangeToVisible(NSRange(location: lineStarts[startLine - 1], length: 0))
    }
    gutter.frame = CGRect(x: 0, y: 0, width: gutter.width, height: bounds.height)
    attachScrollOwner()
    gutter.setNeedsDisplay()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    attachScrollOwner()
  }

  private func attachScrollOwner() {
    guard window != nil else { return }
    var responder = next
    while let current = responder {
      if let owner = current as? UIViewController {
        owner.setContentScrollView(renderMarkdown ? documentScroll : textView, for: .top)
        owner.setContentScrollView(renderMarkdown ? documentScroll : textView, for: .bottom)
        scrollOwner = owner
        return
      }
      responder = current.next
    }
  }

  override func willMove(toWindow newWindow: UIWindow?) {
    super.willMove(toWindow: newWindow)
    guard newWindow == nil, let owner = scrollOwner else { return }
    if owner.contentScrollView(for: .top) === textView || owner.contentScrollView(for: .top) === documentScroll {
      owner.setContentScrollView(nil, for: .top)
      owner.setContentScrollView(nil, for: .bottom)
    }
    scrollOwner = nil
  }

  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory { scheduleRender() }
  }

  override func lodyAppearanceDidChange() {
    backgroundColor = .lodyBackground
    gutter.backgroundColor = .lodyBackground
    scheduleRender()
  }
}

// Soft-wrapped continuation fragments carry no number; only paragraph starts do.
private final class GutterView: UIView {
  weak var textView: UITextView?
  var lineStarts: [Int] = []
  var font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
  var width: CGFloat = 40

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .lodyBackground
    contentMode = .redraw
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func draw(_ rect: CGRect) {
    guard let textView, !lineStarts.isEmpty else { return }
    let layout = textView.layoutManager
    let container = textView.textContainer
    let offset = textView.contentOffset.y - textView.textContainerInset.top
    let visible = CGRect(x: 0, y: offset, width: CGFloat.greatestFiniteMagnitude, height: bounds.height + textView.textContainerInset.top)
    let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: UIColor.tertiaryLabel,
    ]
    UIColor.separator.setFill()
    let top = max(textView.adjustedContentInset.top, layout.usedRect(for: container).minY - offset)
    let bottom = min(bounds.height - textView.adjustedContentInset.bottom, layout.usedRect(for: container).maxY - offset)
    if bottom > top {
      UIRectFillUsingBlendMode(CGRect(x: bounds.width - 0.5, y: top, width: 0.5, height: bottom - top), .normal)
    }
    layout.enumerateLineFragments(forGlyphRange: glyphs) { [self] fragment, _, _, glyphRange, _ in
      let characters = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
      let line = lineIndex(startingAt: characters.location)
      guard let line else { return }
      let y = fragment.origin.y - offset
      let text = String(line + 1) as NSString
      let size = text.size(withAttributes: attributes)
      text.draw(at: CGPoint(x: width - 12 - size.width, y: y + (fragment.height - size.height) / 2), withAttributes: attributes)
    }
  }

  private func lineIndex(startingAt location: Int) -> Int? {
    var low = 0, high = lineStarts.count - 1
    while low <= high {
      let mid = (low + high) / 2
      if lineStarts[mid] == location { return mid }
      if lineStarts[mid] < location { low = mid + 1 } else { high = mid - 1 }
    }
    return nil
  }
}
