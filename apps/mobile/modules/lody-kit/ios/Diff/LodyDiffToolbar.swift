import ExpoModulesCore
import UIKit
import WebKit

/// Bounds discovery to this diff surface; never searches another screen's WebView.
final class LodyDiffSurface: ExpoView {
  private weak var scrollOwner: UIViewController?
  private weak var documentScroll: UIScrollView?
  private weak var toolbar: LodyDiffToolbar?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { detachScrollView() }
    else { setNeedsLayout() }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard window != nil else { return }
    let nextToolbar = descendant(LodyDiffToolbar.self, in: self)
    let nextScroll = descendant(WKWebView.self, in: self)?.scrollView
    if toolbar !== nextToolbar { toolbar?.attachScrollEdge(to: nil) }
    toolbar = nextToolbar
    guard let nextScroll else {
      detachScrollView()
      return
    }
    let changedDocument = documentScroll !== nextScroll
    if changedDocument { detachScrollView() }
    documentScroll = nextScroll
    toolbar = nextToolbar
    var responder: UIResponder? = next
    while let current = responder {
      if let owner = current as? UIViewController {
        if let previous = scrollOwner, previous !== owner {
          LodyScrollEdges.unbind(nextScroll, from: previous)
        }
        scrollOwner = owner
        LodyScrollEdges.bind(nextScroll, to: owner)
        if changedDocument {
          nextScroll.contentInsetAdjustmentBehavior = .automatic
          LodyScrollEdges.navigation(nextScroll)
        }
        toolbar?.attachScrollEdge(to: nextScroll)
        return
      }
      responder = current.next
    }
  }

  private func detachScrollView() {
    toolbar?.attachScrollEdge(to: nil)
    if let scrollOwner, let documentScroll {
      LodyScrollEdges.unbind(documentScroll, from: scrollOwner)
    }
    scrollOwner = nil
    documentScroll = nil
  }

  private func descendant<T: UIView>(_ type: T.Type, in root: UIView) -> T? {
    for child in root.subviews {
      if let found = child as? T { return found }
      if child is WKWebView { continue }
      if let found = descendant(type, in: child) { return found }
    }
    return nil
  }
}

final class LodyDiffToolbar: ExpoView {
  let onStyleChange = EventDispatcher()
  private let container: UIVisualEffectView
  private let statsGlass: UIVisualEffectView
  private let segmentGlass: UIVisualEffectView
  private let stats = UILabel()
  private let segment = UISegmentedControl(items: ["Unified", "Split"])
  var pendingAdd = 0
  var pendingDel = 0
  var pendingBase = ""
  private let scrollEdge = UIScrollEdgeElementContainerInteraction()

  func attachScrollEdge(to scrollView: UIScrollView?) {
    guard scrollEdge.scrollView !== scrollView else { return }
    if let scrollView { LodyScrollEdges.floatingControls(scrollView) }
    scrollEdge.scrollView = scrollView
  }

  required init(appContext: AppContext? = nil) {
    container = UIVisualEffectView(effect: UIGlassContainerEffect())
    statsGlass = UIVisualEffectView(effect: UIGlassEffect())
    let interactive = UIGlassEffect()
    interactive.isInteractive = true
    segmentGlass = UIVisualEffectView(effect: interactive)
    statsGlass.cornerConfiguration = .capsule()
    segmentGlass.cornerConfiguration = .capsule()
    super.init(appContext: appContext)
    scrollEdge.edge = .bottom
    addInteraction(scrollEdge)
    backgroundColor = .clear
    stats.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
    stats.adjustsFontForContentSizeCategory = true
    segment.selectedSegmentIndex = 0
    segment.addTarget(self, action: #selector(styleChanged), for: .valueChanged)

    addSubview(container)
    container.contentView.addSubview(statsGlass)
    container.contentView.addSubview(segmentGlass)
    statsGlass.contentView.addSubview(stats)
    segmentGlass.contentView.addSubview(segment)
    for view in [container, statsGlass, segmentGlass, stats, segment] { view.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([
      container.centerXAnchor.constraint(equalTo: centerXAnchor),
      container.centerYAnchor.constraint(equalTo: centerYAnchor),
      container.heightAnchor.constraint(equalToConstant: 44),
      statsGlass.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor),
      statsGlass.topAnchor.constraint(equalTo: container.contentView.topAnchor),
      statsGlass.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor),
      segmentGlass.leadingAnchor.constraint(equalTo: statsGlass.trailingAnchor, constant: 8),
      segmentGlass.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor),
      segmentGlass.topAnchor.constraint(equalTo: container.contentView.topAnchor),
      segmentGlass.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor),
      stats.leadingAnchor.constraint(equalTo: statsGlass.contentView.leadingAnchor, constant: 16),
      stats.trailingAnchor.constraint(equalTo: statsGlass.contentView.trailingAnchor, constant: -16),
      stats.centerYAnchor.constraint(equalTo: statsGlass.contentView.centerYAnchor),
      segment.leadingAnchor.constraint(equalTo: segmentGlass.contentView.leadingAnchor, constant: 6),
      segment.trailingAnchor.constraint(equalTo: segmentGlass.contentView.trailingAnchor, constant: -6),
      segment.centerYAnchor.constraint(equalTo: segmentGlass.contentView.centerYAnchor),
    ])
  }

  func applyStats() { setStats(add: pendingAdd, del: pendingDel, base: pendingBase) }

  func setStats(add: Int, del: Int, base: String) {
    let text = NSMutableAttributedString()
    if add > 0 {
      text.append(NSAttributedString(string: "+\(add)", attributes: [.foregroundColor: UIColor.systemGreen]))
    }
    if del > 0 {
      if text.length > 0 { text.append(NSAttributedString(string: " ")) }
      text.append(NSAttributedString(string: "−\(del)", attributes: [.foregroundColor: UIColor.systemRed]))
    }
    if !base.isEmpty {
      if text.length > 0 { text.append(NSAttributedString(string: " ")) }
      text.append(NSAttributedString(string: base, attributes: [.foregroundColor: UIColor.secondaryLabel]))
    }
    stats.attributedText = text
    statsGlass.isHidden = text.length == 0
  }

  func setStyle(_ value: String) {
    segment.selectedSegmentIndex = value == "split" ? 1 : 0
  }

  @objc private func styleChanged() {
    onStyleChange(["style": segment.selectedSegmentIndex == 1 ? "split" : "unified"])
  }
}
