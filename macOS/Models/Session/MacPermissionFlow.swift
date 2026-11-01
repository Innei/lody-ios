import Foundation
import LodyCore
import LodyData

@MainActor
final class MacPermissionFlow {
  struct Card: Equatable {
    var permission: SessionPermission
    var options: [SessionPermission.Option]
    var busy: Bool
    var error: String
    var questions: MacQuestionDraft? = nil
    var ready = true
  }

  typealias Detail = @MainActor (SessionPermission) async throws -> [SessionPermission.Option]?
  typealias Respond = @MainActor (SessionPermission, String) async throws -> RuntimeContract.RespondPermissionResultState

  private(set) var card: Card?
  var changed: (() -> Void)?
  private let detail: Detail
  typealias RespondQuestions = @MainActor (SessionPermission, String, [String: RuntimeContract.JSONValue]) async throws -> RuntimeContract.RespondPermissionResultState
  private let respond: Respond
  private let respondQuestions: RespondQuestions
  private var answered: Set<String> = []
  private var task: Task<Void, Never>?

  init(detail: @escaping Detail, respond: @escaping Respond, respondQuestions: @escaping RespondQuestions = { _, _, _ in throw OutboxError.scopeExpired }) {
    self.detail = detail
    self.respond = respond
    self.respondQuestions = respondQuestions
  }

  isolated deinit { task?.cancel() }

  func show(_ permission: SessionPermission?, ready: Bool = true) {
    if card?.ready != ready {
      card?.ready = ready
      changed?()
    }
    guard let permission, !answered.contains(permission.requestId) else {
      guard card != nil else { return }
      task?.cancel()
      card = nil
      changed?()
      return
    }
    guard card?.permission != permission else { return }
    task?.cancel()
    card = Card(permission: permission, options: permission.options ?? [], busy: false, error: "")
    card?.ready = ready
    if let meta = permission.questionMeta { card?.questions = MacQuestionDraft(meta: meta) }
    if permission.kind == "ask_user_question", permission.questionMeta == nil {
      card?.error = Self.message("permission.error.options")
    } else if permission.options == nil {
      task = Task { [weak self, detail] in
        let options = try? await detail(permission)
        guard let self, !Task.isCancelled, card?.permission.requestId == permission.requestId else { return }
        if let options, !options.isEmpty { card?.options = options } else { card?.error = Self.message("permission.error.options") }
        changed?()
      }
    }
    changed?()
  }

  func question(_ action: MacQuestionAction) {
    guard let current = card, current.ready, !current.busy, var draft = current.questions else { return }
    switch action {
    case .select(let index): draft.select(index)
    case .text(let text): draft.setText(text)
    case .page(let index): draft.setPage(index)
    case .submit:
      guard let answers = draft.answers,
            let option = current.options.first(where: { $0.kind?.hasPrefix("allow") == true }) else { return }
      answer(option.optionId, answers: answers)
      return
    }
    card?.questions = draft
    changed?()
  }

  func answer(_ optionId: String, answers: [String: RuntimeContract.JSONValue]? = nil) {
    guard let current = card, current.ready, !current.busy, current.options.contains(where: { $0.optionId == optionId }) else { return }
    if current.questions != nil, answers == nil, current.options.first(where: { $0.optionId == optionId })?.kind?.hasPrefix("allow") == true { return }
    card?.busy = true
    card?.error = ""
    changed?()
    let target = current.permission
    task = Task { [weak self, respond, respondQuestions] in
      let key: String
      do {
        let result: RuntimeContract.RespondPermissionResultState
        if let answers { result = try await respondQuestions(target, optionId, answers) }
        else { result = try await respond(target, optionId) }
        guard let self, !Task.isCancelled, card?.permission == target else { return }
        switch result {
        case .accepted:
          accepted(target.requestId)
          return
        case .stale: key = "permission.error.stale"
        case .conflict: key = "permission.error.answered"
        }
      } catch {
        key = "permission.error.send"
      }
      guard let self, card?.permission.requestId == target.requestId else { return }
      card?.busy = false
      card?.error = Self.message(key)
      changed?()
    }
  }

  func settled() async { await task?.value }

  private func accepted(_ requestId: String) {
    answered.insert(requestId)
    guard card?.permission.requestId == requestId else { return }
    card = nil
    changed?()
  }

  private static func message(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), bundle: .lodyData)
  }
}
