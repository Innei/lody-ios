import ActivityKit
import SwiftUI

// Offline owner of the production widget, independent of account restoration.
// The extension, models, assets and fixture states are the production sources.
@main
struct ActivityVerifyApp: App {
  @State private var selection = "single"
  @State private var result = "Ready"

  var body: some Scene {
    WindowGroup {
      List {
        Text("Live Activity verification").font(.headline)
        Text(result).accessibilityIdentifier("activity-result")
        ForEach(["single", "running", "permission", "question", "done", "failed", "doneMany", "stale", "end"], id: \.self) { name in
          Button(name) { select(name) }.accessibilityIdentifier("activity-\(name)")
        }
      }
      .onOpenURL { url in select(url.lastPathComponent) }
      .task {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-fixture"), arguments.indices.contains(index + 1) {
          select(arguments[index + 1])
        }
      }
    }
  }

  private func select(_ name: String) {
    selection = name
    Task { @MainActor in
      let activities = Activity<LodyActivityAttributes>.activities
      if name == "end" {
        for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
        result = "Ended"
        return
      }
      let states: [String: LodyState] = [
        "single": LiveActivityFixtures.single,
        "running": LiveActivityFixtures.running,
        "permission": LiveActivityFixtures.permission,
        "question": LiveActivityFixtures.question,
        "done": LiveActivityFixtures.done,
        "failed": LiveActivityFixtures.failed,
        "doneMany": LiveActivityFixtures.doneMany,
        "stale": LiveActivityFixtures.single,
      ]
      guard let state = states[name] else { return }
      let content = ActivityContent(state: state, staleDate: name == "stale" ? .now.addingTimeInterval(-1) : .now.addingTimeInterval(1800))
      do {
        if let activity = activities.first {
          await activity.update(content)
        } else {
          _ = try Activity.request(attributes: LiveActivityFixtures.attributes, content: content)
        }
        result = "Showing \(name)"
      } catch {
        result = "Error: \(error.localizedDescription)"
      }
    }
  }
}
