import LodyCore
import ExpoModulesCore
import Foundation

extension DataRuntime {
  private func workspaceCallForRN<C: RuntimeCall>(_ call: C.Type, payload: String, promise: Promise, timeout: Double? = nil,
    project: @escaping @MainActor (C.Result) -> any Encodable = { $0 }) where C.Params: Decodable, C.Result: Encodable {
    guard let workspace, Self.scope(payload)?["workspaceId"] as? String == workspace else {
      fail(promise, "not_ready", LodyStrings.text("native.runtime.sessionNotSynced"))
      return
    }
    callForRN(C.self, payload: payload, inject: ["userId": userId], promise: promise, timeout: timeout, project: project)
  }
  func promptShortcuts(_ payload: String, promise: Promise) {
    workspaceCallForRN(RuntimeContract.Calls.PromptShortcuts.self, payload: payload, promise: promise) { result -> any Encodable in
      switch result {
      case .list(let value): return value.entries
      case .read(let value): return value.shortcut
      case .save(let value): return value.entry
      }
    }
  }
  func remoteSettings(_ payload: String, promise: Promise) {
    workspaceCallForRN(RuntimeContract.Calls.RemoteSettings.self, payload: payload, promise: promise) { $0.settings }
  }
  func memorySettings(_ payload: String, promise: Promise) {
    workspaceCallForRN(RuntimeContract.Calls.MemorySettings.self, payload: payload, promise: promise)
  }
  func agentRoles(_ payload: String, promise: Promise) {
    workspaceCallForRN(RuntimeContract.Calls.AgentRoles.self, payload: payload, promise: promise)
  }
  func publishedShares(_ payload: String, promise: Promise) {
    workspaceCallForRN(RuntimeContract.Calls.PublishedShares.self, payload: payload, promise: promise) { result -> any Encodable in
      switch result {
      case .page(let value): return value
      case .failed(let value): return value
      }
    }
  }
  func mentionCatalog(_ payload: String, promise: Promise) {
    workspaceCallForRN(RuntimeContract.Calls.MentionCatalog.self, payload: payload, promise: promise)
  }
  func creationOptions(_ payload: String, promise: Promise) {
    workspaceCallForRN(RuntimeContract.Calls.CreationOptions.self, payload: payload, promise: promise)
  }
  func localProjects(_ payload: String, promise: Promise) {
    let history = Self.scope(payload)?["action"] as? String == "history"
    workspaceCallForRN(RuntimeContract.Calls.LocalProjects.self, payload: payload, promise: promise,
      timeout: history ? nil : 45) { result -> any Encodable in
      switch result {
      case .cancelled(let value): return value
      case .machines(let value): return value
      case .targets(let value): return value.targets
      case .history(let value): return value
      case .directory(let value): return value
      case .project(let value): return value.project
      }
    }
  }
  func sessionSharing(_ payload: String, promise: Promise) {
    workspaceCallForRN(RuntimeContract.Calls.SessionSharing.self, payload: payload, promise: promise) { result -> any Encodable in
      switch result {
      case .closed: return RuntimeContract.JSONValue.null
      case .state(let value): return value
      }
    }
  }
  func sessionPreview(_ payload: String, promise: Promise) {
    guard Self.scope(payload)?["sessionId"] as? String == sessionId else {
      fail(promise, "not_ready", LodyStrings.text("native.runtime.sessionNotSynced"))
      return
    }
    callForRN(RuntimeContract.Calls.SessionPreview.self, payload: payload, inject: ["userId": userId], promise: promise)
  }
  func iosSimulatorControl(_ payload: String, promise: Promise) {
    workspaceCallForRN(RuntimeContract.Calls.IosSimulatorControl.self, payload: payload, promise: promise)
  }
}
