import ExpoModulesCore
import MarkdownView
import UIKit

final class LodyInlineDiffView: ExpoView {
  let onRender = EventDispatcher()
  let onFail = EventDispatcher()
  private let renderer = InlineDiffRenderer()
  private var path = ""
  private var oldText: String?
  private var newText: String?
  private var renderScheduled = false
  private var lastHeight: CGFloat = 0

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = true
    backgroundColor = .clear
    addSubview(renderer)
  }

  func setPath(_ value: String) { path = value; scheduleRender() }
  func setOldText(_ value: String?) { oldText = value; scheduleRender() }
  func setNewText(_ value: String?) { newText = value; scheduleRender() }

  private func scheduleRender() {
    guard !renderScheduled else { return }
    renderScheduled = true
    DispatchQueue.main.async { [weak self] in
      self?.renderScheduled = false
      self?.render()
    }
  }

  private func render() {
    guard oldText != nil || newText != nil else { return }
    let old = oldText ?? ""
    let new = newText ?? ""
    let document = InlineDiffModel.build(old: old, new: new)
    let bytes = old.utf8.count + new.utf8.count
    renderer.render(document, path: path, highlight: bytes <= 256 * 1024)
    if bytes <= 256 * 1024 {
      applyHighlight(document)
    }
    reportHeight()
    setNeedsLayout()
  }

  private func applyHighlight(_ document: InlineDiffDocument) {
    let language = Self.language(for: path)
    var theme = ChatMarkdownTheme.make(traits: traitCollection, secondary: false)
    theme.fonts.code = UIFont.lodySFMono(ofSize: 13)
    theme.colors.code = .label
    let lines = document.hunks.flatMap(\.lines)
    var texts: [NSAttributedString] = []
    texts.reserveCapacity(lines.count)
    for line in lines {
      let map = CodeHighlighter.current.highlight(key: nil, content: line.text, language: language, theme: theme)
      let attributed = NSMutableAttributedString(attributedString: map.apply(to: line.text.isEmpty ? " " : line.text, with: theme))
      for range in line.emphasis where range.location != NSNotFound && NSMaxRange(range) <= attributed.length {
        attributed.addAttribute(
          .backgroundColor,
          value: InlineDiffRenderer.emphasisTint(for: line.kind),
          range: range
        )
      }
      texts.append(attributed)
    }
    renderer.applyHighlighted(texts)
  }

  private func reportHeight() {
    renderer.layoutIfNeeded()
    let height = renderer.contentHeight
    guard abs(height - lastHeight) > 0.5 else { return }
    lastHeight = height
    onRender(["fileCount": 1, "contentHeight": Double(height)])
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    renderer.frame = bounds
    renderer.layoutIfNeeded()
    reportHeight()
  }

  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    if previous?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory
      || previous?.userInterfaceStyle != traitCollection.userInterfaceStyle
    {
      scheduleRender()
    }
  }

  private static func language(for path: String) -> String? {
    let name = (path as NSString).lastPathComponent.lowercased()
    let ext = (name as NSString).pathExtension
    return [
      "ts": "typescript", "tsx": "typescript", "js": "javascript", "jsx": "javascript",
      "swift": "swift", "py": "python", "rb": "ruby", "go": "go", "rs": "rust",
      "java": "java", "kt": "kotlin", "c": "c", "cpp": "cpp", "cs": "csharp",
      "json": "json", "yml": "yaml", "yaml": "yaml", "md": "markdown",
      "css": "css", "html": "xml", "sh": "bash",
    ][ext.isEmpty ? name : ext]
  }
}