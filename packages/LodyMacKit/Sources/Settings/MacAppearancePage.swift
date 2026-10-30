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

struct MacAppearancePage: View {
  @Bindable var model: MacAppearanceModel

  var body: some View {
    Form {
      Section {
        HStack(alignment: .top, spacing: 18) {
          ForEach(MacTheme.allCases, id: \.self) { theme in
            Button { model.theme = theme } label: {
              VStack(spacing: 6) {
                MacThemeThumbnail(theme: theme, selected: model.theme == theme)
                Text(theme.label).font(.caption)
              }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(theme.label)
            .accessibilityAddTraits(model.theme == theme ? .isSelected : [])
            .accessibilityIdentifier("settings-appearance-theme-\(theme.rawValue)")
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        LabeledContent(String(localized: "mac.settings.accent", bundle: .lodyMac)) {
          HStack(spacing: 8) {
            ForEach(MacAccent.allCases, id: \.self) { accent in
              Button { model.accent = accent } label: {
                MacAccentDot(accent: accent, selected: model.accent == accent)
              }
              .buttonStyle(.plain)
              .help(accent.label)
              .accessibilityLabel(accent.label)
              .accessibilityAddTraits(model.accent == accent ? .isSelected : [])
              .accessibilityIdentifier("settings-appearance-accent-\(accent.rawValue)")
            }
          }
        }
      } header: {
        Text(String(localized: "mac.settings.theme", bundle: .lodyMac))
      }
      Section(String(localized: "mac.settings.section.conversations", bundle: .lodyMac)) {
        LabeledContent(String(localized: "mac.settings.textSize", bundle: .lodyMac)) {
          HStack {
            Slider(value: $model.textSize, in: MacReading.textSizes, step: 1)
              .frame(width: 160)
              .accessibilityIdentifier("settings-appearance-textSize")
            Text(String(format: String(localized: "mac.settings.textSize.value", bundle: .lodyMac), Int(model.textSize)))
              .monospacedDigit()
              .foregroundStyle(.secondary)
              .frame(width: 40, alignment: .trailing)
          }
        }
        Toggle(isOn: $model.fillWidth) {
          Text(String(localized: "mac.settings.fillWidth", bundle: .lodyMac))
          Text(String(localized: "mac.settings.fillWidth.detail", bundle: .lodyMac))
        }
        .accessibilityIdentifier("settings-appearance-fillWidth")
      }
    }
    .formStyle(.grouped)
  }
}

struct MacThemeThumbnail: View {
  let theme: MacTheme
  let selected: Bool

  var body: some View {
    ZStack {
      switch theme {
      case .system:
        HStack(spacing: 0) {
          MacThemeWindow(dark: false).frame(width: 40, alignment: .leading).clipped()
          MacThemeWindow(dark: true).frame(width: 40, alignment: .trailing).clipped()
        }
      case .light: MacThemeWindow(dark: false)
      case .dark: MacThemeWindow(dark: true)
      }
    }
    .frame(width: 80, height: 54)
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(nsColor: .separatorColor)), lineWidth: selected ? 3 : 1)
    )
  }
}

private struct MacThemeWindow: View {
  let dark: Bool

  var body: some View {
    let base = dark ? Color(white: 0.17) : Color(white: 0.96)
    let line = dark ? Color(white: 0.38) : Color(white: 0.78)
    HStack(spacing: 0) {
      (dark ? Color(white: 0.24) : Color(white: 0.88)).frame(width: 22)
      VStack(alignment: .leading, spacing: 5) {
        Capsule().fill(line).frame(width: 34, height: 4)
        Capsule().fill(line).frame(width: 46, height: 4)
        Capsule().fill(.tint).frame(width: 22, height: 4)
      }
      .padding(8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(width: 80, height: 54)
    .background(base)
  }
}

struct MacAccentDot: View {
  let accent: MacAccent
  let selected: Bool

  var body: some View {
    fill
      .frame(width: 18, height: 18)
      .padding(3)
      .overlay(Circle().strokeBorder(selected ? Color.secondary : .clear, lineWidth: 2))
  }

  @ViewBuilder private var fill: some View {
    if accent == .system {
      Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
    } else {
      Circle().fill(Color(nsColor: accent.color))
    }
  }
}
