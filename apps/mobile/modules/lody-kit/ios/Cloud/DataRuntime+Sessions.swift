import LodyCore
import ExpoModulesCore
import Foundation

extension DataRuntime {
  func releaseReserve(_ id: String) {
    reservedSessions.removeAll { $0 == id }
    dispatch(RuntimeContract.Calls.ReleaseReserve.self, .init(sessionId: id))
  }
  func createSession(_ payload: String, promise: Promise) {
    guard let workspace else { fail(promise, "not_ready", LodyStrings.text("native.runtime.sessionNotSynced")); return }
    let user = userId, generation = self.generation
    Task { @MainActor in
      let entitlement = await billing.entitlement(workspace: workspace, user: user)
      guard self.generation == generation, self.workspace == workspace, self.userId == user else {
        promise.resolve(#"{"state":"rejected"}"#); return
      }
      guard self.inWorkspace(payload, sink: .promise(promise)) else { return }
      self.callForRN(RuntimeContract.Calls.CreateSession.self, payload: payload,
        inject: ["billingEntitlement": entitlement ?? NSNull()], promise: promise)
    }
  }
  func workspaceWrite<C: RuntimeCall>(_ call: C.Type, payload: String, promise: Promise) where C.Params: Decodable, C.Result: Encodable {
    guard inWorkspace(payload, sink: .promise(promise)) else { return }
    callForRN(C.self, payload: payload, promise: promise)
  }
  func sessionWrite<C: RuntimeCall>(_ call: C.Type, payload: String, promise: Promise) where C.Params: Decodable, C.Result: Encodable {
    guard inOpenSession(payload, sink: .promise(promise)) else { return }
    callForRN(C.self, payload: payload, promise: promise)
  }
  func workspaceBillingEntitlement(workspace: String, user: String, promise: Promise) {
    guard self.workspace == workspace, userId == user else { promise.resolve("{}"); return }
    let generation = self.generation
    Task { @MainActor in
      let entitlement = await billing.entitlement(workspace: workspace, user: user)
      guard self.generation == generation, self.workspace == workspace, self.userId == user else {
        promise.resolve("{}"); return
      }
      let data = (try? JSONSerialization.data(withJSONObject: entitlement ?? [:])) ?? Data("{}".utf8)
      promise.resolve(String(data: data, encoding: .utf8) ?? "{}")
    }
  }
  func prepareSessionEdit(_ payload: String, promise: Promise) {
    let generation = self.generation
    guard let workspace, let session = sessionId else { promise.reject("not_ready", "Session unavailable"); return }
    Task { @MainActor in
      do {
        let result: String = try await withCheckedThrowingContinuation {
          self.dispatchTurn(payload, sink: .continuation($0), billing: nil, edit: true)
        }
        guard var draft = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any],
              draft["state"] as? String == "ready" else { promise.resolve(result); return }
        var attachments: [[String: Any]] = []
        let originals = draft["attachments"] as? [[String: Any]] ?? []
        guard originals.count <= 16 else { throw SessionAttachments.error(LodyStrings.text("native.attachment.error.limit")) }
        let downloads = AttachmentDownloadBatch()
        // ponytail: download at most 16 originals for the shared local-file composer; use lazy remote previews if large attachments make editing slow.
        for block in originals {
          let image = block["type"] as? String == "image"
          guard let id = block[image ? "imageId" : "fileId"] as? String,
                let editID = block["editId"] as? String else { throw SessionAttachments.error("Invalid attachment") }
          let name = block["fileName"] as? String ?? (image ? "image.jpg" : "file")
          let directory = downloads.makeDirectory()
          let url = try await SessionAttachments.download(workspace: workspace,
            session: block["storageSessionId"] as? String ?? session, fileId: id, fileName: name,
            sizeBytes: block["sizeBytes"] as? Int, directory: directory, image: image)
          guard self.generation == generation, self.sessionId == session else { throw CancellationError() }
          attachments.append(["id": editID, "name": name, "uri": url.absoluteString, "kind": image ? "image" : "file"])
        }
        guard self.generation == generation, self.sessionId == session else { throw CancellationError() }
        draft["attachments"] = attachments
        let encoded = String(data: try JSONSerialization.data(withJSONObject: draft), encoding: .utf8)!
        downloads.handOff()
        promise.resolve(encoded)
      } catch { promise.reject("edit_prepare_failed", error.localizedDescription) }
    }
  }
  func readSessionEdit(_ payload: String, promise: Promise) {
    dispatchTurn(payload, sink: .promise(promise), billing: nil, edit: true)
  }
  func sendTurn(_ payload: String, promise: Promise, edit: Bool = false) {
    guard let workspace else { dispatchTurn(payload, sink: .promise(promise), billing: nil, edit: edit); return }
    let user = userId, generation = self.generation
    Task { @MainActor in
      let entitlement = await billing.entitlement(workspace: workspace, user: user)
      guard self.generation == generation, self.workspace == workspace, self.userId == user else {
        promise.resolve(notSentJSON("native.runtime.connectionSwitched")); return
      }
      let hasAttachments = payload.data(using: .utf8)
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        .flatMap { $0["attachments"] as? [[String: Any]] }
        .map { !$0.isEmpty } ?? false
      if hasAttachments, let quota = await turnQuota(payload, billing: entitlement) {
        promise.resolve(quota); return
      }
      sendTurnWithBilling(payload, promise: promise, billing: entitlement, edit: edit)
    }
  }
  private func turnQuota(_ payload: String, billing: [String: Any]?) async -> String? {
    guard health.ready, contractReady, let channel, workspace != nil, payload.utf8.count <= 128 * 1024,
          let target = Self.scope(payload)?["sessionId"] as? String, !target.isEmpty else {
      return notSentJSON("native.runtime.sessionNotSyncedRetry")
    }
    let entitlement = billing.flatMap { try? RuntimeJSON.decode(RuntimeContract.BillingEntitlement.self, from: $0) }
    let params = RuntimeContract.CheckTurnQuotaParams(sessionId: target, billingEntitlement: entitlement)
    guard case .notSent(let value)? = try? await channel.call(RuntimeContract.Calls.CheckTurnQuota.self, params),
          let data = try? JSONEncoder().encode(RuntimeContract.CheckTurnQuotaResult.notSent(value)) else { return nil }
    return String(decoding: data, as: UTF8.self)
  }
  private func sendTurnWithBilling(_ payload: String, promise: Promise, billing: [String: Any]?, edit: Bool) {
    guard let data = payload.data(using: .utf8), data.count <= 128 * 1024,
          var args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let attachments = args.removeValue(forKey: "attachments") as? [[String: Any]], !attachments.isEmpty else {
      dispatchTurn(payload, sink: .promise(promise), billing: billing, edit: edit); return
    }
    guard health.ready, let workspace,
          let target = args["sessionId"] as? String, !target.isEmpty,
          attachmentTasks[target] == nil else {
      promise.resolve(notSentJSON("native.runtime.sessionNotReady")); return
    }
    if !backgrounded {
      args["backgroundTaskId"] = SessionBackgroundTasks.shared.begin(owner: owner)
    }
    let backgroundTaskId = args["backgroundTaskId"] as? String
    let generation = self.generation
    let sendID = args["id"] as? String ?? ""
    let attempt = UUID()
    let billingTier = billing?["effectivePlanTier"] as? String
    let checkoutPending = billing?["checkoutPending"] as? Bool
    attachmentAttempts[target] = attempt
    attachmentTasks[target] = Task.detached { [weak self] in
      do {
        args["attachmentBlocks"] = try await SessionAttachments.upload(attachments, workspace: workspace, session: target) { [weak self] attachmentID, phase, percent in
          DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == generation, self.workspace == workspace,
              self.attachmentAttempts[target] == attempt, self.attachmentTasks[target] != nil else { return }
            var event: [String: Any] = ["sessionId": target, "sendId": sendID,
              "attachmentId": attachmentID, "phase": phase]
            if let percent { event["percent"] = percent }
            self.emitUploadProgress(event)
          }
        }
        try Task.checkCancellation()
        let prepared = String(data: try JSONSerialization.data(withJSONObject: args), encoding: .utf8)!
        await MainActor.run { [weak self] in
          guard let self, self.generation == generation, !Task.isCancelled else {
            if let backgroundTaskId { SessionBackgroundTasks.shared.finish(backgroundTaskId, success: false) }
            promise.resolve(notSentJSON("native.runtime.connectionSwitched")); return
          }
          self.attachmentTasks[target] = nil
          self.attachmentAttempts[target] = nil
          var projection: [String: Any]?
          if let billingTier, let checkoutPending {
            projection = ["effectivePlanTier": billingTier, "checkoutPending": checkoutPending]
          }
          self.dispatchTurn(prepared, sink: .promise(promise), billing: projection, edit: edit)
        }
      } catch {
        let result = (try? JSONSerialization.data(withJSONObject: ["state": "not_sent", "reason": error.localizedDescription])) ?? Data()
        await MainActor.run { [weak self] in
          if let self, self.generation == generation, !Task.isCancelled {
            self.attachmentTasks[target] = nil
            self.attachmentAttempts[target] = nil
          }
          if let backgroundTaskId { SessionBackgroundTasks.shared.finish(backgroundTaskId, success: false) }
          promise.resolve(String(data: result, encoding: .utf8)!)
        }
      }
    }
  }
  func dispatchTurn(_ payload: String, sink: ReplySink, billing: [String: Any]?, edit: Bool) {
    let args = payload.data(using: .utf8).flatMap { data in
      data.count <= 128 * 1024 ? (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] : nil
    }
    let target = args?["sessionId"] as? String
    var task = args?["backgroundTaskId"] as? String
    let allowed = edit ? target == sessionId : workspace != nil && target?.isEmpty == false
    guard health.ready, contractReady, channel != nil, let args, allowed else {
      if let task { SessionBackgroundTasks.shared.finish(task, success: false) }
      if edit { fail(sink, "not_ready", LodyStrings.text("native.runtime.sessionNotSynced")) }
      else { sink.resolve(notSentJSON("native.runtime.sessionNotSyncedRetry")) }
      return
    }
    var inject: [String: Any] = ["billingEntitlement": billing ?? NSNull()]
    if edit { inject["userId"] = userId }
    if task == nil, !edit || args["action"] as? String == "send", !backgrounded {
      task = SessionBackgroundTasks.shared.begin(owner: owner)
      if let task { inject["backgroundTaskId"] = task }
    }
    if edit {
      turnCall(RuntimeContract.Calls.EditSession.self, payload, inject: inject, sink: sink, task: task)
      return
    }
    for key in ["modelId", "reasoningEffort"] {
      if let value = args[key] { inject[key] = ["value": value] }
    }
    let text = args["text"] as? String ?? ""
    // Catalog expansion precedes the durable send and has its own bounded read.
    let expands = text.contains("$") || text.contains("@session:") || text.contains("@role:")
    turnCall(RuntimeContract.Calls.SendTurn.self, payload, inject: inject, sink: sink, task: task, timeout: expands ? 90 : nil)
  }
  private func turnCall<C: RuntimeCall>(_ call: C.Type, _ payload: String, inject: [String: Any], sink: ReplySink,
    task: String?, timeout: Double? = nil) where C.Params: Decodable, C.Result: Encodable {
    let release: @MainActor (Bool) -> Void = { success in
      if let task { SessionBackgroundTasks.shared.finish(task, success: success) }
    }
    guard let params = rnParams(C.self, payload: payload, inject: inject, sink: sink) else { release(false); return }
    self.call(C.self, params, sink: sink, timeout: timeout, failed: { release(false) }) { result in
      let data = try? JSONEncoder().encode(result)
      let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
      if reply?["state"] as? String != "accepted" && reply?["awaitingGuide"] as? Bool != true {
        release(reply?["state"] as? String == "queued")
      }
      return data.map { String(decoding: $0, as: UTF8.self) }
    }
  }
}

private func notSentJSON(_ key: String) -> String {
  let payload: [String: Any] = ["state": "not_sent", "reason": LodyStrings.text(key)]
  guard let data = try? JSONSerialization.data(withJSONObject: payload),
        let json = String(data: data, encoding: .utf8) else { return #"{"state":"not_sent"}"# }
  return json
}
