import LodyCore
import ExpoModulesCore
import Foundation

extension DataRuntime {
  enum ReplySink {
    case promise(Promise)
    case continuation(CheckedContinuation<String, Error>)

    func resolve(_ value: Any?) {
      switch self {
      case .promise(let promise):
        promise.resolve(value)
      case .continuation(let continuation):
        if let text = value as? String {
          continuation.resume(returning: text)
        } else if value == nil {
          continuation.resume(returning: "")
        } else {
          continuation.resume(returning: String(describing: value as Any))
        }
      }
    }

    func reject(_ error: Error) {
      switch self {
      case .promise(let promise):
        promise.reject(error as NSError)
      case .continuation(let continuation):
        continuation.resume(throwing: error)
      }
    }
  }

  func fail(_ promise: Promise, _ code: String, _ message: String) {
    fail(.promise(promise), code, message)
  }

  // Expo's `reject(code:description:)` drops the description in this version,
  // so every failure reads "undefined reason". Carry the text in an NSError.
  func fail(_ sink: ReplySink, _ code: String, _ message: String) {
    sink.reject(
      NSError(
        domain: "LodyKit.DataRuntime",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "\(code): \(message)"]
      )
    )
  }

  static func scope(_ payload: String) -> [String: Any]? {
    payload.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
  }
  func inOpenSession(_ payload: String, sink: ReplySink) -> Bool {
    guard Self.scope(payload)?["sessionId"] as? String == sessionId else {
      fail(sink, "not_ready", LodyStrings.text("native.runtime.sessionNotSynced"))
      return false
    }
    return true
  }
  func inWorkspace(_ payload: String, sink: ReplySink) -> Bool {
    guard let workspace, Self.scope(payload)?["workspaceId"] as? String == workspace else {
      fail(sink, "not_ready", LodyStrings.text("native.runtime.sessionNotSynced"))
      return false
    }
    return true
  }
  func callForRN<C: RuntimeCall>(_ call: C.Type, payload: String, inject: [String: Any] = [:], promise: Promise, timeout: Double? = nil,
    project: @escaping @MainActor (C.Result) -> any Encodable = { $0 }) where C.Params: Decodable, C.Result: Encodable {
    guard let params = rnParams(C.self, payload: payload, inject: inject, sink: .promise(promise)) else { return }
    self.call(C.self, params, promise: promise, timeout: timeout) { result in
      (try? JSONEncoder().encode(project(result))).map { String(decoding: $0, as: UTF8.self) }
    }
  }
  func rnParams<C: RuntimeCall>(_ call: C.Type, payload: String, inject: [String: Any] = [:], sink: ReplySink) -> C.Params? where C.Params: Decodable {
    guard let data = payload.data(using: .utf8), data.count <= 128 * 1024,
          var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      fail(sink, "not_ready", LodyStrings.text("native.runtime.sessionNotSynced"))
      return nil
    }
    object.merge(inject) { _, injected in injected }
    do { return try RuntimeJSON.decode(C.Params.self, from: object) }
    catch {
      fail(sink, "command_failed", "invalid_params: \(C.method)")
      return nil
    }
  }
  func call<C: RuntimeCall>(_ call: C.Type, _ params: C.Params, promise: Promise, timeout: Double? = nil, resolve: @escaping @MainActor (C.Result) -> Any?) {
    self.call(C.self, params, sink: .promise(promise), timeout: timeout, resolve: resolve)
  }
  func call<C: RuntimeCall>(_ call: C.Type, _ params: C.Params, sink: ReplySink, timeout: Double? = nil,
    failed: @escaping @MainActor () -> Void = {}, resolve: @escaping @MainActor (C.Result) -> Any?) {
    guard health.ready, contractReady, let channel else {
      failed()
      fail(sink, "not_ready", LodyStrings.text("native.runtime.sessionNotSynced"))
      return
    }
    Task { @MainActor in
      do {
        sink.resolve(resolve(try await channel.call(C.self, params, timeout: timeout)))
      } catch let failure as RuntimeFailure {
        failed()
        switch failure.code {
        case "timeout": self.fail(sink, "send_timeout", LodyStrings.text("native.runtime.sendTimeout"))
        case "runtime_replaced": self.fail(sink, "runtime_replaced", LodyStrings.text("native.runtime.replaced"))
        default: self.fail(sink, "command_failed", failure.detail ?? failure.code)
        }
      } catch {
        failed()
        self.fail(sink, "command_failed", error.localizedDescription)
      }
    }
  }
}
