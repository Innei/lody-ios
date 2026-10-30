import Foundation
import LodyData

enum MacSessionAction: String, CaseIterable, Sendable {
  case rename, archive, pin, read, delete
}

@MainActor
struct MacSessionPrompts {
  var rename: @MainActor (SessionItem) async -> String?
  var confirmDelete: @MainActor (SessionItem, _ tabs: Int) async -> Bool
  var blocked: @MainActor (SessionItem) async -> Void
  var toast: @MainActor (_ message: String, _ kind: String) -> Void
}

@MainActor
final class MacSessionActions {
  private let source: MacSessionsSource
  private let prompts: MacSessionPrompts
  private let now: () -> Double
  private var deleting: Set<String> = []

  init(source: MacSessionsSource, prompts: MacSessionPrompts, now: @escaping () -> Double = { Date().timeIntervalSince1970 * 1000 }) {
    self.source = source
    self.prompts = prompts
    self.now = now
  }

  func title(_ action: MacSessionAction, sessionId: String?) -> String {
    let session = sessionId.flatMap { source.read().catalog.session($0) }
    let key = switch action {
    case .rename: "mac.session.rename"
    case .archive: session?.archived == true ? "mac.session.unarchive" : "mac.session.archive"
    case .pin: session?.pinned == true ? "mac.session.unpin" : "mac.session.pin"
    case .read: "mac.session.read"
    case .delete: "mac.session.delete"
    }
    return Self.text(key)
  }

  func isEnabled(_ action: MacSessionAction, sessionId: String?) -> Bool {
    guard let session = sessionId.flatMap({ source.read().catalog.session($0) }) else { return false }
    return action != .read || Self.unread(session)
  }

  func perform(_ action: MacSessionAction, sessionId: String?) async {
    let state = source.read()
    guard let session = sessionId.flatMap({ state.catalog.session($0) }), !state.workspaceId.isEmpty else { return }
    switch action {
    case .rename:
      guard let raw = await prompts.rename(session) else { return }
      let title = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
      guard !title.isEmpty, title != session.title else { return }
      await write(state.workspaceId, session.id, .rename(title), failed: "mac.session.renameFailed")
    case .archive:
      let archived = !session.archived
      await write(state.workspaceId, session.id, .archive(archived), failed: archived ? "mac.session.archiveFailed" : "mac.session.unarchiveFailed",
                  done: archived ? "mac.session.archived" : "mac.session.unarchived")
    case .pin:
      let pinned = !session.pinned
      await write(state.workspaceId, session.id, .pin(pinned), failed: pinned ? "mac.session.pinFailed" : "mac.session.unpinFailed")
    case .read:
      guard Self.unread(session), let message = session.lastMessageAt else { return }
      await write(state.workspaceId, session.id, .read(max(now(), message)), failed: "mac.session.readFailed")
    case .delete:
      await delete(session, in: state)
    }
  }

  private func delete(_ session: SessionItem, in state: SessionListState) async {
    let targets = SessionDeletion.targets(state.catalog.sessions, id: session.id)
    let keys = Set(targets.map { "\(state.workspaceId):\($0.id)" })
    guard deleting.isDisjoint(with: keys) else { return }
    if SessionDeletion.blocked(targets) {
      await prompts.blocked(session)
      return
    }
    guard await prompts.confirmDelete(session, targets.count - 1), deleting.isDisjoint(with: keys) else { return }
    deleting.formUnion(keys)
    defer { deleting.subtract(keys) }
    prompts.toast(Self.text("mac.session.deleting"), "info")
    await write(state.workspaceId, session.id, .delete(targets.map(\.id)), failed: "mac.session.deleteFailed", done: "mac.session.deleted")
  }

  private func write(_ workspace: String, _ id: String, _ change: SessionWrite, failed: String, done: String? = nil) async {
    do {
      try await source.write(workspace, id, change)
      if let done { prompts.toast(Self.text(done), "info") }
    } catch {
      prompts.toast(Self.text(failed), "error")
    }
  }

  static func unread(_ session: SessionItem) -> Bool {
    guard let message = session.lastMessageAt else { return false }
    return message > max(session.lastReadAt ?? 0, session.lastViewedMessageAt ?? 0)
  }

  private static func text(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), bundle: .lodyMac)
  }
}
