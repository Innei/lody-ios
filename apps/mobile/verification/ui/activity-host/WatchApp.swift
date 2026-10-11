import SwiftUI

// This is a verification-only watchOS host, NOT a shipped Watch app or a mock
// implementation. It renders the exact .small production view at HIG sizes.
@main
struct SmallActivityVerifyApp: App {
  private let preferences = UserDefaults.standard
  private var fixture: String { preferences.string(forKey: "fixture") ?? "single" }
  private var reduced: Bool { preferences.bool(forKey: "reduced") }
  private var state: LodyState {
    let states: [String: LodyState] = [
      "single": LiveActivityFixtures.single, "running": LiveActivityFixtures.running,
      "permission": LiveActivityFixtures.permission, "question": LiveActivityFixtures.question,
      "done": LiveActivityFixtures.done, "failed": LiveActivityFixtures.failed,
      "doneMany": LiveActivityFixtures.doneMany, "stale": LiveActivityFixtures.single,
    ]
    return states[fixture] ?? LiveActivityFixtures.single
  }

  var body: some Scene {
    WindowGroup {
      GeometryReader { geometry in
        let narrow = geometry.size.width < 180
        let width: CGFloat = narrow ? 152 : 184
        let height: CGFloat = narrow ? 69.5 : 80.5
        VStack(spacing: 12) {
          Text("Small activity · \(fixture)")
            .font(.system(size: 10)).foregroundStyle(.secondary)
          LodySmallActivityView(state: state, isStale: fixture == "stale")
            .environment(\.isLuminanceReduced, reduced)
            .frame(width: width, height: height)
            .background(Color.white.opacity(reduced ? 0 : 0.11), in: RoundedRectangle(cornerRadius: 19))
            .clipShape(RoundedRectangle(cornerRadius: 19))
            .accessibilityIdentifier("small-activity-\(fixture)")
          Text(reduced ? "Reduced luminance fixture" : "Production view fixture")
            .font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .preferredColorScheme(.dark)
    }
  }
}
