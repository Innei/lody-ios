#if DEBUG
import Foundation
import LodyData

extension MacSessionsSource {
  static let fixtureChanged = Notification.Name("LodyMacSessionsFixtureDidChange")

  static func fixture(_ initial: SessionListState) -> MacSessionsSource {
    let box = FixtureState(initial)
    return MacSessionsSource(changes: [fixtureChanged], read: { box.state }, write: { _, id, write in
      box.apply(id, write)
      NotificationCenter.default.post(name: fixtureChanged, object: nil)
    }, selectWorkspace: { _ in })
  }
}

@MainActor
private final class FixtureState {
  var state: SessionListState

  init(_ state: SessionListState) { self.state = state }

  func apply(_ id: String, _ write: SessionWrite) {
    if case .delete(let ids) = write {
      state.catalog.sessions.removeAll { ids.contains($0.id) }
      return
    }
    guard let index = state.catalog.sessions.firstIndex(where: { $0.id == id }) else { return }
    switch write {
    case .archive(let on): state.catalog.sessions[index].archived = on
    case .pin(let on): state.catalog.sessions[index].pinned = on
    case .read(let at): state.catalog.sessions[index].lastReadAt = at
    case .rename(let title): state.catalog.sessions[index].title = title
    case .delete: break
    }
  }
}
#endif
