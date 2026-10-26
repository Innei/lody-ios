import LodyCore
import ExpoModulesCore
import Foundation

extension DataRuntime {
  private func workspaceCallForRN<C: RuntimeCall>(_ call: C.Type, payload: String, promise: Promise, timeout: Double? = nil,
    project: @escaping @MainActor (C.Result) -> any Encodable = { $0 }) where C.Params: Decodable, C.Result: Encodable {
    workspaceCallForRN(C.self, payload: payload, sink: .promise(promise), timeout: timeout, project: project)
  }
  private func workspaceCallForRN<C: RuntimeCall>(_ call: C.Type, payload: String, sink: ReplySink, timeout: Double? = nil,
    project: @escaping @MainActor (C.Result) -> any Encodable = { $0 }) where C.Params: Decodable, C.Result: Encodable {
    guard let workspace, Self.scope(payload)?["workspaceId"] as? String == workspace else {
      fail(sink, "not_ready", LodyStrings.text("native.runtime.sessionNotSynced"))
      return
    }
    callForRN(C.self, payload: payload, inject: ["userId": userId], sink: sink, timeout: timeout, project: project)
  }
  func mentionCatalog(_ payload: String, promise: Promise) {
    workspaceCallForRN(RuntimeContract.Calls.MentionCatalog.self, payload: payload, promise: promise)
  }
  func creationOptions(_ payload: String, promise: Promise) {
    workspaceCallForRN(RuntimeContract.Calls.CreationOptions.self, payload: payload, promise: promise)
  }
  func creationOptions(_ payload: String, sink: ReplySink) {
    workspaceCallForRN(RuntimeContract.Calls.CreationOptions.self, payload: payload, sink: sink)
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
