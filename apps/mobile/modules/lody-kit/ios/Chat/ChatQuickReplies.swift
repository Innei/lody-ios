import SwiftUI
import UIKit

struct ChatQuickReply: Decodable, Equatable {
  let id: String
  let label: String
  let message: String
}

struct ChatPreviewChip: Decodable, Equatable {
  struct Action: Decodable, Equatable {
    let id: String
    let title: String
    let symbol: String
    var destructive: Bool?
  }
  let label: String
  let symbol: String
  let state: String
  let accessibilityLabel: String
  var actions: [Action]?
}

struct ChatContextChipContent: View {
  var label = ""
  var symbol = "safari"
  var connecting = false
  var dimmed = false
  var compact = false

  var body: some View {
    HStack(spacing: 6) {
      ZStack {
        if connecting {
          ProgressView().controlSize(.small).transition(.blurReplace)
        } else {
          Image(systemName: symbol)
            .imageScale(.small)
            .contentTransition(.symbolEffect(.replace))
            .transition(.blurReplace)
        }
      }
      if !compact {
        Text(label)
          .lineLimit(1)
          .truncationMode(.middle)
          .contentTransition(.interpolate)
          .transition(.blurReplace)
      }
    }
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(Color(uiColor: dimmed ? .secondaryLabel : .systemBlue))
    .padding(.leading, compact ? 0 : 10)
    .padding(.trailing, compact ? 0 : 12)
  }
}

final class ChatContextChipButton: UIButton {
  private let hosting = UIHostingController(rootView: ChatContextChipContent())
  private let clip = UIView()
  private var width: NSLayoutConstraint!
  private var height: NSLayoutConstraint!

  override init(frame: CGRect) {
    super.init(frame: frame)
    var configuration = UIButton.Configuration.glass()
    configuration.cornerStyle = .capsule
    configuration.contentInsets = .zero
    self.configuration = configuration
    hosting.safeAreaRegions = []
    hosting.sizingOptions = []
    hosting.view.backgroundColor = .clear
    hosting.view.isOpaque = false
    hosting.view.isUserInteractionEnabled = false
    hosting.view.accessibilityElementsHidden = true
    clip.clipsToBounds = true
    clip.isUserInteractionEnabled = false
    clip.layer.cornerCurve = .continuous
    clip.addSubview(hosting.view)
    addSubview(clip)
    accessibilityIdentifier = "session-preview"
    translatesAutoresizingMaskIntoConstraints = false
    width = widthAnchor.constraint(equalToConstant: ChatQuickRepliesView.chipHeight)
    height = heightAnchor.constraint(equalToConstant: ChatQuickRepliesView.chipHeight)
    NSLayoutConstraint.activate([width, height])
  }

  required init?(coder: NSCoder) { fatalError() }

  func apply(_ content: ChatContextChipContent, animation: Animation?) {
    if let animation {
      withAnimation(animation) { hosting.rootView = content }
    } else {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction) { hosting.rootView = content }
    }
    let chip = ChatQuickRepliesView.chipHeight
    let fitting = hosting.sizeThatFits(in: CGSize(width: 220, height: chip))
    height.constant = chip
    width.constant = content.compact ? chip : min(220, max(chip, ceil(fitting.width)))
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    clip.frame = bounds
    clip.layer.cornerRadius = bounds.height / 2
    // The capsule springs toward its new width; the content already sits at that width from the
    // leading edge so the clip reveals it instead of SwiftUI re-centering it every frame.
    UIView.performWithoutAnimation {
      hosting.view.frame = CGRect(x: 0, y: 0, width: width.constant, height: bounds.height)
    }
    bringSubviewToFront(clip)
  }
}

final class ChatQuickRepliesView: UIScrollView {
  static var titleFont: UIFont { UIFont.preferredFont(forTextStyle: .subheadline) }
  static var chipHeight: CGFloat { titleFont.lineHeight + 16 }

  private let stack = UIStackView()
  private let separator = UIView()
  private lazy var separatorWidth = separator.widthAnchor.constraint(equalToConstant: 1)
  private var contextChip: ChatContextChipButton?
  private var rendered: [ChatQuickReply] = []
  private var renderedActions: [ChatPreviewChip.Action]?
  private var buttons: [UIButton] = []
  var onSelect: ((String) -> Void)?
  var onPreview: ((String) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    accessibilityIdentifier = "session-quick-replies"
    clipsToBounds = false
    showsHorizontalScrollIndicator = false
    alwaysBounceHorizontal = false
    isDirectionalLockEnabled = true
    contentInsetAdjustmentBehavior = .never
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 8
    separator.backgroundColor = .separator
    separator.isHidden = true
    separator.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([separatorWidth, separator.heightAnchor.constraint(equalToConstant: 20)])
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor, constant: -16),
      stack.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
      stack.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
      stack.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
    ])
  }

  required init?(coder: NSCoder) { fatalError() }

  func render(_ items: [ChatQuickReply], context: ChatPreviewChip?, showsReplies: Bool, compact: Bool, visible: Bool, animated: Bool = false) {
    let showsRow = visible && (context != nil || (showsReplies && !items.isEmpty))
    let visibilityChanged = isUserInteractionEnabled != showsRow
    let motion = animated && window != nil && !UIAccessibility.isReduceMotionEnabled
    isUserInteractionEnabled = showsRow
    accessibilityElementsHidden = !showsRow
    if visibilityChanged {
      if showsRow { isHidden = false }
      let update = { self.alpha = showsRow ? 1 : 0 }
      if motion {
        UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .curveEaseOut], animations: update) { _ in
          self.isHidden = !self.isUserInteractionEnabled
        }
      } else {
        update()
        isHidden = !showsRow
      }
    }
    let swaps = motion && contextChip?.isHidden == false
    let repliesShown = showsReplies || !showsRow
    let contextAppears = context != nil && contextChip?.isHidden != false
    var retiring: [UIView] = []
    if items != rendered {
      rendered = items
      contentOffset = .zero
      retiring = stack.arrangedSubviews.filter { $0 is UIButton && $0 !== contextChip }
      retiring.forEach { $0.isUserInteractionEnabled = false }
      buttons.removeAll { $0 !== contextChip }
      UIView.performWithoutAnimation {
        for item in items {
          let button = chip(item)
          if swaps || !repliesShown { button.isHidden = true; button.alpha = 0 }
          stack.addArrangedSubview(button)
        }
        stack.layoutIfNeeded()
      }
      if !swaps { retiring.forEach { $0.removeFromSuperview() } }
    }
    if let context { updateContext(context, compact: compact, motion: motion) }
    let layout = {
      self.show(self.contextChip, context != nil)
      self.show(self.separator, context != nil && repliesShown && !items.isEmpty)
      for button in self.buttons where button !== self.contextChip { self.show(button, repliesShown) }
      for view in retiring where view.superview != nil { self.show(view, false) }
      if contextAppears { self.contentOffset.x = 0 }
      self.layoutIfNeeded()
    }
    if motion && contextChip?.window != nil {
      UIView.animate(Self.motion, changes: layout) { retiring.forEach { $0.removeFromSuperview() } }
    } else {
      layout()
      retiring.forEach { $0.removeFromSuperview() }
    }
  }

  private static let motion = Animation.smooth(duration: 0.35)

  // UIStackView miscounts repeated isHidden writes inside animations and leaves a shown view hidden.
  private func show(_ view: UIView?, _ shown: Bool) {
    guard let view else { return }
    if view.isHidden == shown { view.isHidden = !shown }
    view.alpha = shown ? 1 : 0
  }

  private func updateContext(_ context: ChatPreviewChip, compact: Bool, motion: Bool) {
    let chip = contextChip ?? makeContextChip()
    chip.apply(ChatContextChipContent(
      label: context.label,
      symbol: context.symbol,
      connecting: context.state == "connecting",
      dimmed: context.state == "unavailable",
      compact: compact
    ), animation: motion && !chip.isHidden ? Self.motion : nil)
    chip.accessibilityLabel = context.accessibilityLabel
    guard context.actions != renderedActions else { return }
    renderedActions = context.actions
    chip.menu = context.actions.flatMap { actions in
      actions.isEmpty ? nil : UIMenu(children: actions.map { action in
        UIAction(title: action.title, image: UIImage(systemName: action.symbol),
                 attributes: action.destructive == true ? .destructive : []) { [weak self] _ in
          self?.onPreview?(action.id)
        }
      })
    }
  }

  private func makeContextChip() -> ChatContextChipButton {
    let chip = ChatContextChipButton()
    chip.isHidden = true
    chip.alpha = 0
    chip.setContentHuggingPriority(.required, for: .horizontal)
    chip.addAction(UIAction { [weak self] _ in self?.onPreview?("open") }, for: .touchUpInside)
    stack.insertArrangedSubview(chip, at: 0)
    stack.insertArrangedSubview(separator, at: 1)
    separatorWidth.constant = 1 / max(1, traitCollection.displayScale)
    buttons.insert(chip, at: 0)
    contextChip = chip
    return chip
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }
    let hit = super.hitTest(point, with: event)
    if let hit, hit !== self { return hit }
    for button in buttons where !button.isHidden {
      let frame = button.convert(button.bounds, to: self)
      let target = frame.insetBy(
        dx: -max(0, 44 - frame.width) / 2,
        dy: -max(0, 44 - frame.height) / 2
      )
      if target.contains(point) { return button }
    }
    return hit === self ? nil : hit
  }

  private func chip(_ item: ChatQuickReply) -> UIButton {
    var configuration = UIButton.Configuration.glass()
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    configuration.title = item.label
    configuration.titleLineBreakMode = .byTruncatingTail
    configuration.baseForegroundColor = .label
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = Self.titleFont
      return outgoing
    }
    let button = UIButton(configuration: configuration)
    button.accessibilityIdentifier = "quick-reply:\(item.id)"
    button.accessibilityHint = LodyStrings.text("native.chat.quickReply.sendHint")
    button.addAction(UIAction { [weak self] _ in self?.onSelect?(item.id) }, for: .touchUpInside)
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    let textWidth = (item.label as NSString).boundingRect(
      with: CGSize(width: .greatestFiniteMagnitude, height: Self.titleFont.lineHeight),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: Self.titleFont],
      context: nil
    ).width
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.heightAnchor.constraint(equalToConstant: Self.chipHeight),
      button.widthAnchor.constraint(equalToConstant: max(44, ceil(textWidth) + 24)),
    ])
    buttons.append(button)
    return button
  }
}
