import ExpoModulesCore
import UIKit

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

  required init(appContext: AppContext? = nil) {
    if #available(iOS 26, *) {
      container = UIVisualEffectView(effect: UIGlassContainerEffect())
      statsGlass = UIVisualEffectView(effect: UIGlassEffect())
      let interactive = UIGlassEffect()
      interactive.isInteractive = true
      segmentGlass = UIVisualEffectView(effect: interactive)
      statsGlass.cornerConfiguration = .capsule()
      segmentGlass.cornerConfiguration = .capsule()
    } else {
      container = UIVisualEffectView(effect: nil)
      statsGlass = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
      segmentGlass = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
      for glass in [statsGlass, segmentGlass] {
        glass.layer.cornerRadius = 22
        glass.layer.cornerCurve = .continuous
        glass.clipsToBounds = true
      }
    }
    super.init(appContext: appContext)
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
      text.append(NSAttributedString(string: "+\(add)", attributes: [.foregroundColor: UIColor.systemBlue]))
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
