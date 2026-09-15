import SwiftUI
import UIKit

@Observable
final class ChatNumericTextModel {
  var attributed = AttributedString()
  var value = ""
  var shines = false
}

struct ChatNumericTextBridge: View {
  var model: ChatNumericTextModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    laidOutGlyphs
      .contentTransition(.numericText())
      .overlay {
        if model.shines && !reduceMotion { shine }
      }
      .padding(0)
  }

  private var glyphs: some View {
    Text(model.attributed)
      .multilineTextAlignment(.leading)
  }

  private var laidOutGlyphs: some View {
    glyphs
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var shine: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: false)) { context in
      let period = 1.5
      let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
      GeometryReader { geo in
        let width = max(1, geo.size.width)
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0.25),
            .init(color: Color.white.opacity(0.64), location: 0.5),
            .init(color: .clear, location: 0.75),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: width, height: max(1, geo.size.height))
        .offset(x: (-1 + 2 * progress) * width)
      }
      .mask(alignment: .topLeading) {
        laidOutGlyphs
      }
    }
    .allowsHitTesting(false)
  }
}

final class ChatNumericTextHost: UIView {
  private let model: ChatNumericTextModel
  private let hosting: UIHostingController<ChatNumericTextBridge>

  override init(frame: CGRect) {
    let model = ChatNumericTextModel()
    self.model = model
    hosting = UIHostingController(rootView: ChatNumericTextBridge(model: model))
    super.init(frame: frame)
    hosting.safeAreaRegions = []
    hosting.sizingOptions = []
    hosting.view.backgroundColor = .clear
    hosting.view.isOpaque = false
    hosting.view.insetsLayoutMarginsFromSafeArea = false
    hosting.view.isUserInteractionEnabled = false
    hosting.view.isAccessibilityElement = false
    hosting.view.accessibilityElementsHidden = true
    clipsToBounds = true
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    accessibilityElementsHidden = true
    addSubview(hosting.view)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func apply(text: NSAttributedString, animated: Bool, shines: Bool) {
    let attributed = AttributedString(text)
    let value = text.string
    let update = {
      self.model.attributed = attributed
      self.model.value = value
      self.model.shines = shines
    }
    let motion = animated
      && window != nil
      && !value.isEmpty
      && !model.value.isEmpty
      && model.value != value
      && !UIAccessibility.isReduceMotionEnabled
    if motion {
      withAnimation(.default, update)
    } else {
      var transaction = Transaction()
      transaction.disablesAnimations = true
      withTransaction(transaction, update)
    }
  }

  func reset() {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
      model.attributed = AttributedString()
      model.value = ""
      model.shines = false
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    hosting.view.frame = bounds
  }

  override func sizeThatFits(_ size: CGSize) -> CGSize {
    hosting.sizeThatFits(
      in: CGSize(width: max(1, size.width), height: UIView.layoutFittingExpandedSize.height)
    )
  }
}
