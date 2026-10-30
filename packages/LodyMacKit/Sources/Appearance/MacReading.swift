import Foundation

struct MacReading: Equatable, Sendable {
  static let textSizes: ClosedRange<Double> = 11...18
  static let textSizeKey = "lody.mac.reading.textSize"
  static let fillWidthKey = "lody.mac.reading.fillWidth"
  static let standard = MacReading(textSize: 13, fillWidth: false)

  var textSize: Double
  var fillWidth: Bool

  init(textSize: Double, fillWidth: Bool) {
    self.textSize = min(max(textSize, Self.textSizes.lowerBound), Self.textSizes.upperBound)
    self.fillWidth = fillWidth
  }

  static func current(_ defaults: UserDefaults = .standard) -> MacReading {
    let size = defaults.object(forKey: textSizeKey) as? Double ?? standard.textSize
    return MacReading(textSize: size, fillWidth: defaults.bool(forKey: fillWidthKey))
  }

  func save(_ defaults: UserDefaults = .standard) {
    defaults.set(textSize, forKey: Self.textSizeKey)
    defaults.set(fillWidth, forKey: Self.fillWidthKey)
    NotificationCenter.default.post(name: .lodyMacReadingDidChange, object: nil)
  }
}

extension Notification.Name {
  static let lodyMacReadingDidChange = Notification.Name("lodyMacReadingDidChange")
}
