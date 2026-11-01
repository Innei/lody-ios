import Foundation
import LodyCore
import LodyData

@MainActor
final class MacQueueModel {
  typealias Item = RuntimeContract.SessionQueueItem
  private let sessionId: String
  private let userId: String
  private let service: MacQueueService
  private(set) var items: [Item] = []
  private(set) var busy = false
  private(set) var committing = false
  private(set) var blocked = false
  private(set) var error = ""
  private(set) var editing: Item?
  private(set) var conflictText: String?
  var text = ""
  var changed: (() -> Void)?
  var onSteer: ((String) -> Void)?
  var canSteer: (_ index: Int) -> Bool = { _ in false }

  init(sessionId: String, userId: String, service: MacQueueService) {
    self.sessionId = sessionId
    self.userId = userId
    self.service = service
  }

  func reload() async { await run(.list(.init(sessionId: sessionId, userId: userId))) }

  func begin(_ item: Item) async {
    guard !busy, !blocked, !item.editing, editing == nil, conflictText == nil else { return }
    let token = UUID().uuidString
    await run(.begin(.init(sessionId: sessionId, userId: userId, id: item.id, revision: item.revision, editToken: token)))
    guard !blocked, let owned = items.first(where: { $0.id == item.id && $0.editToken == token }) else { return }
    editing = owned
    text = owned.text
    changed?()
  }

  func save() async {
    guard !busy, !blocked, let item = editing, let token = item.editToken else { return }
    await run(.save(.init(sessionId: sessionId, userId: userId, id: item.id, revision: item.revision, editToken: token, text: text)))
    if error.isEmpty { editing = nil; changed?() }
  }

  func cancel() async {
    guard !busy, !blocked, let item = editing, let token = item.editToken else { return }
    await run(.cancel(.init(sessionId: sessionId, userId: userId, id: item.id, revision: item.revision, editToken: token)))
    if error.isEmpty { editing = nil; changed?() }
  }

  func remove(_ item: Item) async {
    await run(.remove(.init(sessionId: sessionId, userId: userId, id: item.id, revision: item.revision)))
  }

  func move(_ item: Item, over target: Item) async {
    await run(.move(.init(sessionId: sessionId, userId: userId, id: item.id, revision: item.revision, overId: target.id)))
  }

  func steer(_ item: Item) {
    guard !busy, !blocked, !item.editing, let index = items.firstIndex(where: { $0.id == item.id }),
          canSteer(index), let messageId = item.messageId else { return }
    onSteer?(messageId)
    changed?()
  }

  func discardConflict() {
    conflictText = nil
    error = ""
    changed?()
  }

  private func run(_ params: RuntimeContract.SessionQueueParams) async {
    guard !busy else { return }
    if blocked, case .list = params {} else if blocked { return }
    busy = true
    if case .list = params { committing = false } else { committing = true }
    error = ""
    changed?()
    defer { busy = false; committing = false; changed?() }
    do {
      let result = try await service.request(params)
      items = result.items
      if result.state != .unknown, let current = editing {
        let finished: Bool
        switch params {
        case .save, .cancel: finished = result.state == .ready
        default: finished = false
        }
        if finished { editing = nil }
        else if !items.contains(where: { $0.id == current.id && $0.editing && $0.editToken == current.editToken && $0.revision == current.revision }) {
          conflictText = text
          editing = nil
        }
      }
      switch result.state {
      case .ready:
        blocked = false
        if conflictText != nil { error = Self.message("mac.queue.editingLost") }
      case .stale: error = Self.message(conflictText == nil ? "mac.queue.stale" : "mac.queue.editingLost")
      case .unknown:
        blocked = true
        error = Self.message("mac.queue.unknown")
      }
    } catch { self.error = Self.message("mac.queue.failed") }
  }

  private static func message(_ key: String) -> String { String(localized: String.LocalizationValue(key), bundle: .lodyMac) }
}
