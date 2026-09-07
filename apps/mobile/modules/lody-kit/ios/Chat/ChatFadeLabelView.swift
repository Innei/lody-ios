import CoreText
import Litext
import UIKit

final class ChatFadeLayout: TextLabel.Layout {
  var fades: () -> [ChatTextFade.RangeFade] = { [] }

  override func draw(line: CTLine, at index: Int, in context: CGContext) {
    let time = CACurrentMediaTime()
    let lineRange = CTLineGetStringRange(line)
    let active = fades().filter {
      $0.opacity(at: time) < 1 && NSIntersectionRange($0.range, NSRange(location: lineRange.location, length: lineRange.length)).length > 0
    }
    guard !active.isEmpty else { CTLineDraw(line, context); return }
    func opacity(at character: CFIndex) -> CGFloat {
      active.reduce(1) { NSLocationInRange(character, $1.range) ? min($0, CGFloat($1.opacity(at: time))) : $0 }
    }
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
      let count = CTRunGetGlyphCount(run)
      guard count > 0 else { continue }
      let runRange = CTRunGetStringRange(run)
      guard active.contains(where: { NSIntersectionRange($0.range, NSRange(location: runRange.location, length: runRange.length)).length > 0 }) else {
        CTRunDraw(run, context, CFRange(location: 0, length: 0))
        continue
      }
      var indices = [CFIndex](repeating: 0, count: count)
      CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
      var start = 0
      var current = opacity(at: indices[0])
      for glyph in 1...count {
        let next = glyph < count ? opacity(at: indices[glyph]) : -1
        guard next != current else { continue }
        context.saveGState()
        context.setAlpha(current)
        CTRunDraw(run, context, CFRange(location: start, length: glyph - start))
        context.restoreGState()
        start = glyph
        current = next
      }
    }
  }
}

/// Fades newly rendered graphemes in while a message streams. Ticks only redraw;
/// they never touch the attributed string or the layout.
final class ChatFadeLabelView: TextLabelView, UIGestureRecognizerDelegate {
  private var fade = ChatTextFade()
  private var timer: Timer?
  private var animateNext = false
  private var resetNext = false
  private var renderedLayout: TextLabel.Layout?

  override init(frame: CGRect) {
    super.init(frame: frame)
    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(selectWord(_:)))
    longPress.cancelsTouchesInView = false
    longPress.delegate = self
    addGestureRecognizer(longPress)
  }

  func prepare(animate: Bool, reset: Bool) {
    animateNext = animate
    if reset { resetNext = true }
  }

  override var attributedText: NSAttributedString {
    didSet {
      let animate = animateNext && window != nil && !UIAccessibility.isReduceMotionEnabled
      fade.update(attributedText.string, animate: animate, at: CACurrentMediaTime(), reset: resetNext)
      resetNext = false
      pokeTimer()
    }
  }

  override func makeTextLayout(_ attributedText: NSAttributedString) -> TextLabel.Layout {
    let layout = ChatFadeLayout(attributedString: attributedText)
    layout.fades = { [weak self] in self?.fade.active ?? [] }
    renderedLayout = layout
    return layout
  }

  @objc private func selectWord(_ gesture: UILongPressGestureRecognizer) {
    guard gesture.state == .began, let layout = renderedLayout else { return }
    let point = gesture.location(in: self)
    let layoutPoint = CGPoint(x: point.x, y: layout.containerSize.height - point.y)
    guard let index = layout.textIndex(at: layoutPoint) else { return }
    let text = layout.attributedString.string as NSString
    var selected = NSRange(location: NSNotFound, length: 0)
    text.enumerateSubstrings(
      in: NSRange(location: 0, length: text.length),
      options: [.byWords, .substringNotRequired]
    ) { _, range, _, stop in
      guard NSLocationInRange(index, range) else { return }
      selected = range
      stop.pointee = true
    }
    if selected.location != NSNotFound { selectionRange = selected }
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool { true }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { fade.update(attributedText.string, animate: false, at: CACurrentMediaTime(), reset: true) }
    pokeTimer()
  }

  private func pokeTimer() {
    let keep = window != nil && !UIAccessibility.isReduceMotionEnabled && fade.isAnimating(at: CACurrentMediaTime())
    guard keep else { timer?.invalidate(); timer = nil; return }
    guard timer == nil else { return }
    let ticker = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
      guard let self else { timer.invalidate(); return }
      self.setNeedsDisplay()
      if self.window == nil || !self.fade.isAnimating(at: CACurrentMediaTime()) {
        timer.invalidate()
        self.timer = nil
      }
    }
    timer = ticker
    RunLoop.main.add(ticker, forMode: .common)
  }
}
