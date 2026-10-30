import Observation
import SwiftUI

@MainActor
struct MacAppearanceServices {
  var theme: @MainActor () -> MacTheme
  var setTheme: @MainActor (MacTheme) -> Void
  var accent: @MainActor () -> MacAccent
  var setAccent: @MainActor (MacAccent) -> Void
  var reading: @MainActor () -> MacReading
  var setReading: @MainActor (MacReading) -> Void

  static var live: MacAppearanceServices {
    MacAppearanceServices(
      theme: { .current() }, setTheme: { $0.apply() },
      accent: { .current() }, setAccent: { $0.apply() },
      reading: { .current() }, setReading: { $0.save() }
    )
  }
}
