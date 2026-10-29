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
  }

  typealias Detail = @MainActor (SessionPermission) async throws -> [SessionPermission.Option]?
  typealias Respond = @MainActor (SessionPermission, String) async throws -> RuntimeContract.RespondPermissionResultState

  private(set) var card: Card?
  var changed: (() -> Void)?
  private let detail: Detail
  private let respond: Respond
  private var answered: Set<String> = []
  private var task: Task<Void, Never>?

  init(detail: @escaping Detail, respond: @escaping Respond) {
    self.detail = detail
    self.respond = respond
  }

  isolated deinit { task?.cancel() }

  func show(_ permission: SessionPermission?) {
    guard let permission, !answered.contains(permission.requestId) else {
      guard card != nil else { return }
      task?.cancel()
      card = nil
      changed?()
      return
    }
    guard card?.permission.requestId != permission.requestId else { return }
    task?.cancel()
    card = Card(permission: permission, options: permission.options ?? [], busy: false, error: "")
    if permission.kind == "ask_user_question" {
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

  func answer(_ optionId: String) {
    guard let current = card, !current.busy, current.options.contains(where: { $0.optionId == optionId }) else { return }
    card?.busy = true
    card?.error = ""
    changed?()
    let target = current.permission
    task = Task { [weak self, respond] in
      let key: String
      do {
        switch try await respond(target, optionId) {
        case .accepted:
          self?.accepted(target.requestId)
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
