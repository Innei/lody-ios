import UIKit

@MainActor
final class InboxProjectIndex: UIView {
  static let width: CGFloat = 44
  static let room: CGFloat = 40
  static var hideDelay: TimeInterval = 0.8

  var jump: ((String) -> Void)?
  var visibilityChanged: ((Bool) -> Void)?
  var enabled = false {
    didSet { if !enabled { present(false) } }
  }
  private(set) var shown = false
  private let glass = UIVisualEffectView(effect: UIGlassEffect())
  private var cells: [InboxIndexCell] = []
  private var items: [InboxIndexItem] = []
  private var current: String?
  private var scrubbed: Int?
  private var touching = false
  private var scrolling = false
  private var hideWork: DispatchWorkItem?
  private let haptics = UISelectionFeedbackGenerator()

  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "project-index"
    accessibilityLabel = String(localized: "inbox.projectIndex.accessibility", bundle: .lody)
    accessibilityContainerType = .semanticGroup
    glass.cornerConfiguration = .capsule()
    glass.isUserInteractionEnabled = false
    addSubview(glass)
    isHidden = true
    alpha = 0
    transform = Self.away
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  private static var away: CGAffineTransform {
    CGAffineTransform(translationX: 80, y: 0).scaledBy(x: 0.8, y: 0.8)
  }

  func update(_ next: [InboxIndexItem]) {
    guard next != items else { return }
    items = next
    cells.forEach { $0.removeFromSuperview() }
    cells = next.map { item in
      let cell = InboxIndexCell(item)
      cell.activated = { [weak self] in self?.select(item.id) }
      addSubview(cell)
      return cell
    }
    setCurrent(current)
    setNeedsLayout()
  }

  func height(available: CGFloat) -> CGFloat {
    InboxProjectIndexModel.pitch(count: items.count, available: available - 16) * CGFloat(items.count) + 16
  }

  func setCurrent(_ id: String?) {
    current = id
    for cell in cells { cell.current = cell.item.id == id }
  }

  func setScrolling(_ value: Bool) {
    scrolling = value
    if value { present(true) } else { scheduleHide() }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    glass.frame = bounds.insetBy(dx: 4, dy: 0)
    let pitch = InboxProjectIndexModel.pitch(count: cells.count, available: bounds.height - 16)
    for (index, cell) in cells.enumerated() {
      cell.frame = CGRect(x: 0, y: 8 + CGFloat(index) * pitch, width: bounds.width, height: pitch)
    }
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    touching = true
    hideWork?.cancel()
    haptics.prepare()
    scrub(touches)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    scrub(touches)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    endTouch()
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    endTouch()
  }

  private func scrub(_ touches: Set<UITouch>) {
    guard let touch = touches.first, !cells.isEmpty else { return }
    let pitch = InboxProjectIndexModel.pitch(count: cells.count, available: bounds.height - 16)
    let index = InboxProjectIndexModel.item(at: touch.location(in: self).y - 8, count: cells.count, pitch: pitch)
    guard index != scrubbed else { return }
    if scrubbed != nil { haptics.selectionChanged() }
    scrubbed = index
    select(cells[index].item.id)
  }

  private func endTouch() {
    touching = false
    scrubbed = nil
    scheduleHide()
  }

  private func select(_ id: String) {
    setCurrent(id)
    jump?(id)
  }

  private func scheduleHide() {
    hideWork?.cancel()
    guard !touching, !scrolling else { return }
    let work = DispatchWorkItem { [weak self] in self?.present(false) }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay, execute: work)
  }

  private func present(_ visible: Bool) {
    let next = visible && enabled && items.count > 1
    guard next != shown else { return }
    shown = next
    hideWork?.cancel()
    if next { isHidden = false }
    UIView.animate(springDuration: 0.45, bounce: 0.2, options: [.allowUserInteraction, .beginFromCurrentState]) {
      self.alpha = next ? 1 : 0
      self.transform = next ? .identity : Self.away
      self.visibilityChanged?(next)
    } completion: { _ in
      if !self.shown { self.isHidden = true }
    }
  }
}

@MainActor
private final class InboxIndexCell: UIView {
  let item: InboxIndexItem
  var activated: (() -> Void)?
  var current = false {
    didSet { highlight.isHidden = !current }
  }
  private let highlight = UIView()
  private let icon = UIImageView()
  private let monogram = UILabel()
  private let dot = UIView()

  init(_ item: InboxIndexItem) {
    self.item = item
    super.init(frame: .zero)
    isAccessibilityElement = true
    accessibilityTraits = .button
    accessibilityIdentifier = "project-index:\(item.id)"
    accessibilityLabel = item.title
    isUserInteractionEnabled = false
    highlight.backgroundColor = .lodySelection
    highlight.isHidden = true
    icon.contentMode = .scaleAspectFit
    icon.tintColor = .lodySecondary
    icon.clipsToBounds = true
    monogram.font = LodyDesign.font(.caption1, size: 11, weight: .semibold)
    monogram.textColor = .lodySecondary
    monogram.textAlignment = .center
    dot.layer.cornerRadius = 3.5
    dot.layer.borderWidth = 1.5
    dot.layer.borderColor = UIColor.systemBackground.cgColor
    for view in [highlight, icon, monogram, dot] { addSubview(view) }
    configure()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func accessibilityActivate() -> Bool {
    activated?()
    return true
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let side = min(28, bounds.height)
    highlight.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    highlight.layer.cornerRadius = side / 2
    let glyph = min(16, bounds.height - 4)
    icon.frame = CGRect(x: bounds.midX - glyph / 2, y: bounds.midY - glyph / 2, width: glyph, height: glyph)
    monogram.frame = icon.frame
    dot.frame = CGRect(x: icon.frame.maxX - 3, y: icon.frame.minY - 4, width: 7, height: 7)
  }

  private func configure() {
    dot.isHidden = item.dot == nil
    dot.backgroundColor = item.dot == .live ? .lodySignal : .lodyAttention
    if !item.symbol.isEmpty {
      icon.image = UIImage(systemName: item.symbol)
      return
    }
    guard let url = LodyListPhoto.url(item.image) else {
      if item.monogram.isEmpty {
        icon.image = UIImage(systemName: "folder")
      } else {
        monogram.text = item.monogram.uppercased()
      }
      return
    }
    icon.layer.cornerRadius = 4
    icon.image = LodyListPhoto.image(for: url, shape: .original) { [weak self] photo in self?.icon.image = photo }
      ?? UIImage(systemName: "folder")
  }
}
