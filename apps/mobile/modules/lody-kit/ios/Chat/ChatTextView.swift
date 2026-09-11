import UIKit

/// TextKit lays out once per content/width change. Fade ticks only draw glyphs;
/// they never rebuild attributed strings, remeasure cells or refresh the list.
final class ChatTextView: UIView {
  private let storage = NSTextStorage()
  var attributedTextValue: NSAttributedString { NSAttributedString(attributedString: storage) }
  private let manager = NSLayoutManager()
  private let container = NSTextContainer(size: .zero)
  private var fade = ChatTextFade()
  private var timer: Timer?
  private var shineEnabled = false
  var onLink: ((String) -> Void)? {
    didSet { isUserInteractionEnabled = onLink != nil }
  }
  var linkHitHeight: CGFloat = .greatestFiniteMagnitude

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    isUserInteractionEnabled = false
    contentMode = .redraw
    container.lineFragmentPadding = 0
    container.lineBreakMode = .byWordWrapping
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openLink(_:))))
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  var linkActions: [UIAccessibilityCustomAction] {
    var actions: [UIAccessibilityCustomAction] = []
    storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
      guard let href = value as? String else { return }
      let label = (storage.string as NSString).substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
      actions.append(UIAccessibilityCustomAction(name: label) { [weak self] _ in self?.onLink?(href); return true })
    }
    return actions
  }

  func link(at point: CGPoint) -> String? {
    guard bounds.contains(point), point.y < linkHitHeight else { return nil }
    layout(width: bounds.width)
    var closest: (href: String, distance: CGFloat)?
    storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
      guard let href = value as? String else { return }
      let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      manager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
        let hit = rect.insetBy(dx: min(0, (rect.width - 44) / 2), dy: min(0, (rect.height - 44) / 2))
        guard hit.contains(point), rect.minY < self.linkHitHeight else { return }
        let distance = hypot(max(rect.minX - point.x, point.x - rect.maxX, 0), max(rect.minY - point.y, point.y - rect.maxY, 0))
        if closest == nil || distance < closest!.distance { closest = (href, distance) }
      }
    }
    return closest?.href
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    onLink != nil && link(at: point) != nil
  }

  @objc private func openLink(_ gesture: UITapGestureRecognizer) {
    if let href = link(at: gesture.location(in: self)) { onLink?(href) }
  }

  func setText(_ text: NSAttributedString, animate: Bool = false, reset: Bool = false) {
    fade.update(text.string, animate: animate && window != nil && !UIAccessibility.isReduceMotionEnabled,
      at: CACurrentMediaTime(), reset: reset)
    if !storage.isEqual(to: text) { storage.setAttributedString(text) }
    setNeedsDisplay()
    pokeDisplayTimer()
  }

  func setShine(_ on: Bool) {
    shineEnabled = on
    setNeedsDisplay()
    pokeDisplayTimer()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      timer?.invalidate(); timer = nil
      fade.update(storage.string, animate: false, at: CACurrentMediaTime(), reset: true)
    }
    pokeDisplayTimer()
  }

  override func sizeThatFits(_ size: CGSize) -> CGSize {
    layout(width: size.width)
    let used = manager.usedRect(for: container)
    return CGSize(width: ceil(used.maxX), height: ceil(used.maxY))
  }

  func lineAdvances(width: CGFloat) -> [CGFloat] {
    layout(width: width)
    var previous: CGFloat = 0
    var advances: [CGFloat] = []
    manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, _, _ in
      advances.append(max(0, rect.maxY - previous))
      previous = rect.maxY
    }
    return advances
  }

  private var shining: Bool { shineEnabled && !UIAccessibility.isReduceMotionEnabled }

  private func pokeDisplayTimer() {
    let keep = window != nil && !UIAccessibility.isReduceMotionEnabled
      && (shineEnabled || fade.isAnimating(at: CACurrentMediaTime()))
    if keep {
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
    } else if timer != nil {
      timer?.invalidate()
      timer = nil
    }
  }

  private func layout(width: CGFloat) {
    let size = CGSize(width: max(1, width), height: .greatestFiniteMagnitude)
    if container.size != size { container.size = size }
    manager.ensureLayout(for: container)
  }

  private func shineMask(overlay: CGRect) -> CGImage? {
    let size = bounds.size
    guard size.width >= 1, size.height >= 1 else { return nil }
    let scale = max(1, traitCollection.displayScale)
    let pixels = CGSize(width: ceil(size.width * scale), height: ceil(size.height * scale))
    guard let bitmap = CGContext(
      data: nil,
      width: Int(pixels.width),
      height: Int(pixels.height),
      bitsPerComponent: 8,
      bytesPerRow: Int(pixels.width),
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    bitmap.translateBy(x: 0, y: pixels.height)
    bitmap.scaleBy(x: scale, y: -scale)
    bitmap.setFillColor(gray: 0, alpha: 1)
    bitmap.fill(CGRect(origin: .zero, size: size))
    let gray = CGColorSpaceCreateDeviceGray()
    let colors = [
      CGColor(gray: 0, alpha: 1),
      CGColor(gray: 0, alpha: 1),
      CGColor(gray: 1, alpha: 1),
      CGColor(gray: 0, alpha: 1),
      CGColor(gray: 0, alpha: 1),
    ] as CFArray
    let locations: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
    guard let gradient = CGGradient(colorsSpace: gray, colors: colors, locations: locations) else { return nil }
    let angle = 120 * CGFloat.pi / 180
    let direction = CGPoint(x: sin(angle), y: -cos(angle))
    let extent = hypot(overlay.width, overlay.height)
    let center = CGPoint(x: overlay.midX, y: overlay.midY)
    bitmap.saveGState()
    bitmap.clip(to: overlay)
    bitmap.drawLinearGradient(
      gradient,
      start: CGPoint(x: center.x - direction.x * extent / 2, y: center.y - direction.y * extent / 2),
      end: CGPoint(x: center.x + direction.x * extent / 2, y: center.y + direction.y * extent / 2),
      options: []
    )
    bitmap.restoreGState()
    return bitmap.makeImage()
  }

  private func drawShine(_ context: CGContext, range: NSRange) {
    let used = manager.usedRect(for: container)
    let textWidth = max(1, used.width)
    let period = 1.5
    let progress = CGFloat(CACurrentMediaTime().truncatingRemainder(dividingBy: period) / period)
    let overlay = CGRect(
      x: used.minX + (-1 + 2 * progress) * textWidth,
      y: 0,
      width: textWidth,
      height: max(1, bounds.height)
    )
    manager.drawBackground(forGlyphRange: range, at: .zero)
    manager.drawGlyphs(forGlyphRange: range, at: .zero)
    guard let mask = shineMask(overlay: overlay) else { return }
    context.saveGState()
    context.clip(to: bounds, mask: mask)
    context.setBlendMode(.copy)
    context.setAlpha(0.32)
    manager.drawBackground(forGlyphRange: range, at: .zero)
    manager.drawGlyphs(forGlyphRange: range, at: .zero)
    context.restoreGState()
  }

  override func draw(_ rect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    layout(width: bounds.width)
    // UIView retains this drawing while its parent scrolls. Draw the whole text
    // layer so newly exposed lines are already present in its backing store.
    let visible = manager.glyphRange(forBoundingRect: bounds, in: container)
    guard visible.length > 0 else { return }
    if shining {
      drawShine(context, range: visible)
      return
    }
    let time = CACurrentMediaTime()
    var groups: [(range: NSRange, opacity: CGFloat)] = []
    if !UIAccessibility.isReduceMotionEnabled {
      for character in fade.active where character.opacity(at: time) < 1 {
        let glyphs = NSIntersectionRange(manager.glyphRange(forCharacterRange: character.range, actualCharacterRange: nil), visible)
        guard glyphs.length > 0 else { continue }
        let opacity = CGFloat(character.opacity(at: time))
        // Text shaping can join characters into one glyph (e.g. ligatures).
        if let last = groups.last, NSIntersectionRange(last.range, glyphs).length > 0 {
          groups[groups.count - 1] = (NSUnionRange(last.range, glyphs), min(last.opacity, opacity))
        } else { groups.append((glyphs, opacity)) }
      }
    }
    func drawRange(_ range: NSRange, opacity: CGFloat) {
      guard range.length > 0 else { return }
      context.saveGState()
      context.setAlpha(opacity)
      manager.drawBackground(forGlyphRange: range, at: .zero)
      manager.drawGlyphs(forGlyphRange: range, at: .zero)
      context.restoreGState()
    }
    var cursor = visible.location
    for group in groups {
      drawRange(NSRange(location: cursor, length: max(0, group.range.location - cursor)), opacity: 1)
      drawRange(group.range, opacity: group.opacity)
      cursor = NSMaxRange(group.range)
    }
    drawRange(NSRange(location: cursor, length: max(0, NSMaxRange(visible) - cursor)), opacity: 1)
  }
}
