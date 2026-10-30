import UIKit

@MainActor final class LodyTentacle {
  private let rail = CAShapeLayer()
  private let signal = CAGradientLayer()
  private let signalPath = CAShapeLayer()

  init(in host: CALayer) {
    for shape in [rail, signalPath] {
      shape.fillColor = nil
      shape.lineCap = .round
      shape.lineJoin = .round
    }
    rail.lineWidth = 1
    signalPath.lineWidth = 1.5
    signalPath.strokeColor = UIColor.black.cgColor
    signal.startPoint = CGPoint(x: 0.5, y: 0)
    signal.endPoint = CGPoint(x: 0.5, y: 1)
    signal.mask = signalPath
    host.addSublayer(rail)
    host.addSublayer(signal)
  }

  static func branch(trunk: CGFloat, to end: CGPoint, height: CGFloat, last: Bool) -> UIBezierPath {
    let path = UIBezierPath()
    let fork = max(0, end.y - 14)
    path.move(to: CGPoint(x: trunk, y: 0))
    path.addLine(to: CGPoint(x: trunk, y: fork))
    path.addCurve(
      to: end,
      controlPoint1: CGPoint(x: trunk - 2, y: end.y - 6),
      controlPoint2: CGPoint(x: trunk + 4, y: end.y)
    )
    if !last {
      path.move(to: CGPoint(x: trunk, y: fork))
      path.addLine(to: CGPoint(x: trunk, y: height))
    }
    return path
  }

  func apply(_ path: UIBezierPath, live: Bool, frame: CGRect, traits: UITraitCollection) {
    let drawn = path.isEmpty ? nil : path.cgPath
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    rail.frame = frame
    signal.frame = frame
    signalPath.frame = signal.bounds
    rail.strokeColor = UIColor.lodyRail.resolvedColor(with: traits).cgColor
    signal.colors = [
      UIColor.lodySignal.resolvedColor(with: traits).withAlphaComponent(0.75).cgColor,
      UIColor.lodySignalTail.resolvedColor(with: traits).withAlphaComponent(0.6).cgColor,
    ]
    rail.path = live ? nil : drawn
    rail.isHidden = live || drawn == nil
    signalPath.path = live ? drawn : nil
    signal.isHidden = !live || drawn == nil
    CATransaction.commit()
  }
}
