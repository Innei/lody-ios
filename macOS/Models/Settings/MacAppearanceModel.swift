import Observation
import SwiftUI

@MainActor
@Observable
final class MacAppearanceModel {
  @ObservationIgnored private let services: MacAppearanceServices
  private var reading: MacReading

  var theme: MacTheme {
    didSet { services.setTheme(theme) }
  }

  var accent: MacAccent {
    didSet { services.setAccent(accent) }
  }

  init(services: MacAppearanceServices) {
    self.services = services
    theme = services.theme()
    accent = services.accent()
    reading = services.reading()
  }

  var textSize: Double {
    get { reading.textSize }
    set { save(MacReading(textSize: newValue.rounded(), fillWidth: reading.fillWidth)) }
  }

  var fillWidth: Bool {
    get { reading.fillWidth }
    set { save(MacReading(textSize: reading.textSize, fillWidth: newValue)) }
  }

  private func save(_ next: MacReading) {
    reading = next
    services.setReading(next)
  }
}
