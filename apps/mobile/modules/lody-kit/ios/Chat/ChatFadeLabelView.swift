import CoreText
import Litext
import UIKit

final class ChatFadeLayout: TextLabel.Layout {
  var fades: () -> [ChatTextFade.RangeFade] = { [] }
  var shines: () -> Bool = { false }
  var displayScale: () -> CGFloat = { 1 }

  override func draw(in context: CGContext, visibleRect: CGRect?) {
    super.draw(in: context, visibleRect: visibleRect)
    guard shines() else { return }
    let textWidth = min(
      containerSize.width,
      max(1, sizeThatFits(CGSize(width: containerSize.width, height: .greatestFiniteMagnitude)).width)
    )
    let bounds = CGRect(origin: .zero, size: containerSize)
    let overlay = ChatTextShine.overlay(
      for: CGRect(x: 0, y: 0, width: textWidth, height: containerSize.height),
      height: containerSize.height,
      at: CACurrentMediaTime()
    )
    guard let mask = ChatTextShine.mask(
      size: containerSize,
      scale: displayScale(),
      overlay: overlay
    ) else { return }
    context.saveGState()
    context.clip(to: bounds, mask: mask)
    context.setBlendMode(.copy)
    context.setAlpha(0.32)
    super.draw(in: context, visibleRect: visibleRect)
    context.restoreGState()
  }

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
final class ChatFadeLabelView: TextLabelView {
  private var fade = ChatTextFade()
  private var timer: Timer?
  private var animateNext = false
  private var resetNext = false
  private var wasAnimating = false
  private var shineEnabled = false

  func setShine(_ on: Bool) {
    shineEnabled = on
    setNeedsDisplay()
    pokeTimer()
  }

  func prepare(animate: Bool, reset: Bool) {
    animateNext = animate
    if reset { resetNext = true }
  }

  override var attributedText: NSAttributedString {
    didSet {
      let animate = animateNext && window != nil && !UIAccessibility.isReduceMotionEnabled
      guard animate else { finishAnimation(); return }
      if !wasAnimating && !resetNext {
        fade.update(oldValue.string, animate: false, at: CACurrentMediaTime(), reset: true)
      }
      fade.update(attributedText.string, animate: animate, at: CACurrentMediaTime(), reset: resetNext)
      resetNext = false
      wasAnimating = true
      pokeTimer()
    }
  }

  func finishAnimation() {
    fade = ChatTextFade()
    wasAnimating = false
    resetNext = false
    timer?.invalidate()
    timer = nil
    setNeedsDisplay()
    pokeTimer()
  }

  override func makeTextLayout(_ attributedText: NSAttributedString) -> TextLabel.Layout {
    let layout = ChatFadeLayout(attributedString: attributedText)
    layout.fades = { [weak self] in self?.fade.active ?? [] }
    layout.shines = { [weak self] in
      self?.shineEnabled == true && !UIAccessibility.isReduceMotionEnabled
    }
    layout.displayScale = { [weak self] in max(1, self?.traitCollection.displayScale ?? 1) }
    return layout
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { finishAnimation() }
    pokeTimer()
  }

  private func pokeTimer() {
    let keep = window != nil && !UIAccessibility.isReduceMotionEnabled
      && (shineEnabled || fade.isAnimating(at: CACurrentMediaTime()))
    guard keep else { timer?.invalidate(); timer = nil; return }
    guard timer == nil else { return }
    let ticker = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
      guard self != nil else { timer.invalidate(); return }
      MainActor.assumeIsolated {
        guard let self else { return }
        self.setNeedsDisplay()
        if self.window == nil || UIAccessibility.isReduceMotionEnabled
          || !(self.shineEnabled || self.fade.isAnimating(at: CACurrentMediaTime())) {
          self.timer?.invalidate()
          self.timer = nil
        }
      }
    }
    timer = ticker
    RunLoop.main.add(ticker, forMode: .common)
  }
}

/// Litext only selects on double-tap. Table cells and code text are plain
/// `TextLabelView`s built inside MarkdownView, so the word selection is a
/// recognizer attached from outside rather than a label subclass.
final class ChatWordSelection: UILongPressGestureRecognizer, UIGestureRecognizerDelegate {
  static func attach(under view: UIView) {
    for subview in view.subviews {
      if let label = subview as? TextLabelView,
         !(label.gestureRecognizers ?? []).contains(where: { $0 is ChatWordSelection }) {
        label.addGestureRecognizer(ChatWordSelection())
      }
      attach(under: subview)
    }
  }

  init() {
    super.init(target: nil, action: nil)
    addTarget(self, action: #selector(selectWord))
    cancelsTouchesInView = false
    delegate = self
  }

  @objc private func selectWord() {
    guard state == .began, let label = view as? TextLabelView else { return }
    let layout = TextLabel.Layout(attributedString: label.attributedText)
    layout.containerSize = label.bounds.size
    let point = location(in: label)
    guard let index = layout.textIndex(at: CGPoint(x: point.x, y: layout.containerSize.height - point.y)) else { return }
    let text = label.attributedText.string as NSString
    var selected = NSRange(location: NSNotFound, length: 0)
    text.enumerateSubstrings(
      in: NSRange(location: 0, length: text.length),
      options: [.byWords, .substringNotRequired]
    ) { _, range, _, stop in
      guard NSLocationInRange(index, range) else { return }
      selected = range
      stop.pointee = true
    }
    if selected.location != NSNotFound { label.selectionRange = selected }
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool { true }
}
