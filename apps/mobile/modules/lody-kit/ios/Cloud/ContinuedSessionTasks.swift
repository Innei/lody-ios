import BackgroundTasks
import UIKit

/// Main-queue ownership. Expiration releases the background allowance without
/// cancelling the remote agent; only a new user send requests another task.
@available(iOS 26.0, *)
final class ContinuedSessionTasks {
  static let shared = ContinuedSessionTasks()
  private let prefix = "app.innei.lody.session-sync."
  private struct Work {
    let owner: String
    var task: BGContinuedProcessingTask?
    var completed: Int64 = 0
  }
  private var work: [String: Work] = [:]
  #if DEBUG
  private(set) var debugState = "idle"
  var debugCount: Int { work.count }
  func debugExpire() {
    for current in work.values { current.task?.expirationHandler?() }
  }
  #endif

  func begin(owner: String) -> String? {
    guard UIApplication.shared.applicationState == .active else { return nil }
    let id = prefix + UUID().uuidString
    let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: .main) { [weak self] task in
      guard let self, let task = task as? BGContinuedProcessingTask,
            var current = self.work[task.identifier] else {
        task.setTaskCompleted(success: false)
        return
      }
      #if DEBUG
      self.debugState = "running"
      #endif
      current.task = task
      self.work[task.identifier] = current
      task.expirationHandler = { [weak self, weak task] in
        DispatchQueue.main.async {
          guard let self, let task, self.work[task.identifier]?.task === task else { return }
          self.finish(task.identifier, success: false)
          #if DEBUG
          self.debugState = "expired"
          #endif
        }
      }
      // Three observed milestones, never a made-up percentage of agent work.
      task.progress.totalUnitCount = 3
      task.progress.completedUnitCount = current.completed
      self.updateTitle(task, completed: current.completed)
    }
    guard registered else {
      #if DEBUG
      debugState = "unavailable"
      NSLog("LodyBackground registration rejected")
      #endif
      return nil
    }
    work[id] = Work(owner: owner)
    let request = BGContinuedProcessingTaskRequest(
      identifier: id,
      title: LodyStrings.text("native.session.sync.title"),
      subtitle: LodyStrings.text("native.session.sync.sending")
    )
    request.strategy = .fail
    do {
      #if DEBUG
      debugState = "submitted"
      #endif
      try BGTaskScheduler.shared.submit(request)
      return id
    } catch {
      work[id] = nil
      #if DEBUG
      debugState = "unavailable"
      NSLog("LodyBackground submission failed: %@", String(describing: error))
      #endif
      return nil
    }
  }

  func update(_ value: [String: Any], owner: String) {
    guard let id = value["id"] as? String, var current = work[id], current.owner == owner,
          let state = value["state"] as? String else { return }
    switch state {
    case "completed", "waiting":
      current.task?.updateTitle(
        LodyStrings.text("native.session.sync.title"),
        subtitle: LodyStrings.text(state == "waiting" ? "native.session.sync.needsApproval" : "native.session.sync.synced")
      )
      finish(id, success: true)
    case "failed": finish(id, success: false)
    case "sent", "receiving":
      let completed: Int64 = state == "sent" ? 1 : 2
      guard completed > current.completed else { return }
      current.completed = completed
      work[id] = current
      if let task = current.task {
        task.progress.completedUnitCount = current.completed
        updateTitle(task, completed: current.completed)
      }
    default: break
    }
  }

  private func updateTitle(_ task: BGContinuedProcessingTask, completed: Int64) {
    let subtitles = [
      0: LodyStrings.text("native.session.sync.sending"),
      1: LodyStrings.text("native.session.sync.waitingReply"),
    ]
    task.updateTitle(
      LodyStrings.text("native.session.sync.title"),
      subtitle: subtitles[Int(completed)] ?? LodyStrings.text("native.session.sync.receiving")
    )
  }

  func finish(_ id: String, success: Bool) {
    guard let current = work.removeValue(forKey: id) else { return }
    #if DEBUG
    debugState = success ? "completed" : "stopped"
    #endif
    if let task = current.task {
      task.expirationHandler = nil
      if success { task.progress.completedUnitCount = task.progress.totalUnitCount }
      task.setTaskCompleted(success: success)
    } else {
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
    }
  }

  func finishAll(owner: String) {
    for (id, current) in work where current.owner == owner { finish(id, success: false) }
  }
}
