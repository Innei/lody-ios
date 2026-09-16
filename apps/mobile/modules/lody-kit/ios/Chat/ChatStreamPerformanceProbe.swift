import UIKit
import MarkdownView

/// Offline fixture only. Samples main-run-loop delivery, not GPU-presented FPS.
@MainActor
final class ChatStreamPerformanceProbe: NSObject {
  private weak var view: LodyChatView?
  private var link: CADisplayLink?
  private var started = 0.0
  private var previous = 0.0
  private var received = 0
  private var ended = 0.0
  private var caughtUp = 0.0
  private var samples: [[String: Double]] = []
  private var commits: [Double] = []
  private var layoutChecks: [[String: Any]] = []

  init(_ view: LodyChatView) {
    self.view = view
    super.init()
    layoutChecks = Self.checkMarkdownLayout()
    let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
    self.link = link
    link.add(to: .main, forMode: .common)
  }

  func receive(_ entries: [ChatEntry]) {
    guard let entry = entries.last, entry.id == "stream-perf-answer" else { return }
    received = entry.items.first?.text?.utf16.count ?? 0
    if started == 0, received > 0 {
      started = CACurrentMediaTime()
      previous = started
    }
    if entry.finished, ended == 0 { ended = CACurrentMediaTime() }
  }

  func commit(milliseconds: Double) { if started > 0 { commits.append(milliseconds) } }

  @objc private func tick(_ link: CADisplayLink) {
    guard let view else { stop(); return }
    guard view.window != nil, started > 0 else { return }
    let now = CACurrentMediaTime()
    let shown = view.rows["stream-perf-answer:text"]?.text.utf16.count ?? 0
    samples.append(["t": now - started, "dt": now - previous,
      "budget": link.targetTimestamp - link.timestamp,
      "received": Double(received), "shown": Double(shown),
      "lag": Double(max(0, received - shown)), "offset": view.collection.contentOffset.y,
      "bottom": view.bottomOffset, "following": view.followsBottom ? 1 : 0])
    previous = now
    if ended > 0, shown == received, !view.rendering, !view.applying,
       abs(view.bottomOffset - view.collection.contentOffset.y) <= 1, caughtUp == 0 {
      caughtUp = now
    }
    guard (caughtUp > 0 && now - caughtUp > 1) || now - started > 40 else { return }
    let report: [String: Any] = [
      "metric": "CADisplayLink main-run-loop delivery; not GPU-presented FPS",
      "configuration": "Debug", "syntheticTokensPerSecond": 300, "utf16UnitsPerToken": 4,
      "received": received, "shown": shown, "seconds": now - started,
      "inputSeconds": ended > 0 ? ended - started : -1,
      "catchUpSeconds": caughtUp > 0 ? caughtUp - ended : -1,
      "commitsMs": commits, "samples": samples, "layoutChecks": layoutChecks,
    ]
    do {
      let data = try JSONSerialization.data(withJSONObject: report, options: .sortedKeys)
      try data.write(to: FileManager.default.temporaryDirectory
        .appendingPathComponent("lody-stream-performance-\(UUID().uuidString).json"), options: .atomic)
      view.setNavigationSubtitle("Stream benchmark saved")
    } catch { view.setNavigationSubtitle("Stream benchmark failed") }
    stop()
  }

  func stop() { link?.invalidate(); link = nil }

  private static func checkMarkdownLayout() -> [[String: Any]] {
    let store = ChatMarkdownStore(traits: .current)
    let fixtures = [
      "paragraphs": "First **bold** paragraph.\n\nSecond paragraph with `code` and 👩🏽‍💻.",
      "heading-list": "## Heading\n\nA paragraph.\n\n- First item\n- Second item\n\n### Next heading\n\nFinal paragraph.",
      "rich": "> Quoted text\n\n```swift\nlet x = 1\n```\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\nFinal paragraph.",
    ]
    var checks = fixtures.sorted(by: { $0.key < $1.key }).map { name, source -> [String: Any] in
      let full = FileMarkdownView()
      full.setContentImmediately(FileMarkdownView.content(MarkdownContent(parserResult: store.parser.parse(source), theme: store.theme)), theme: store.theme)
      let reference = ceil(full.boundingSize(for: 350).height)
      let split = store.view(id: name, text: source, secondary: false, streaming: true, width: 350)
      return ["name": name, "referenceHeight": reference, "blockHeight": split.measuredHeight,
        "difference": abs(reference - split.measuredHeight)]
    }
    let view = store.view(id: "reuse", text: "Stable prefix.\n\nTail", secondary: false, streaming: true, width: 350)
    let first = view.subviews.first as! FileMarkdownView
    let stableText = first.textLabelView.attributedText
    let next = store.view(id: "reuse", text: "Stable prefix.\n\nTail grows", secondary: false, streaming: true, width: 350)
    checks.append(["name": "reuse", "sameSizingAndDisplayView": view === next,
      "stablePrefixUntouched": first.textLabelView.attributedText === stableText])
    let completed = store.view(id: "reuse", text: "Stable prefix.\n\nTail grows", secondary: false, streaming: false, width: 350)
    let label = (completed.subviews.first as! FileMarkdownView).textLabelView
    label.selectAll()
    let selected = label.selectionRange.map { (label.attributedText.string as NSString).substring(with: $0) } ?? ""
    checks.append(["name": "selection", "completedMessageSelectsAcrossBlocks":
      completed.subviews.count == 1 && selected.contains("Stable prefix.") && selected.contains("Tail grows")])
    let reference = store.view(id: "reference", text: "[link][ref]\n\nTail", secondary: false, streaming: true, width: 350)
    _ = store.view(id: "reference", text: "[link][ref]\n\nTail\n\n[ref]: https://example.com", secondary: false, streaming: true, width: 350)
    let resolved = (reference.subviews.first as! FileMarkdownView).textLabelView.attributedText.string
    checks.append(["name": "reference", "lateReferenceResolved": resolved.trimmingCharacters(in: .whitespacesAndNewlines) == "link"])
    return checks
  }
}
