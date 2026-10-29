import Foundation
import LodyData

@MainActor
protocol MacStreamingTab: AnyObject {
  var sessionId: String? { get }
  func setStreaming(_ on: Bool)
}

// DataRuntime streams one session at a time, so only the selected tab holds a live feed.
@MainActor
final class MacTabCoordinator {
  static let shared = MacTabCoordinator()
  private var tabs: [ObjectIdentifier: () -> MacStreamingTab?] = [:]
  private weak var selected: MacStreamingTab?

  var streamingSession: String? { selected?.sessionId }

  func add(_ tab: MacStreamingTab) {
    tabs[ObjectIdentifier(tab)] = { [weak tab] in tab }
  }

  func remove(_ tab: MacStreamingTab) {
    tabs[ObjectIdentifier(tab)] = nil
    if selected === tab {
      tab.setStreaming(false)
      selected = nil
    }
  }

  func select(_ tab: MacStreamingTab) {
    guard selected !== tab else {
      tab.setStreaming(true)
      return
    }
    selected?.setStreaming(false)
    selected = tab
    tab.setStreaming(true)
  }

  func status(of tab: MacStreamingTab, catalog: SessionCatalog) -> String? {
    tab.sessionId.flatMap { catalog.session($0)?.status }
  }
}

enum MacTabBadge: Equatable {
  case approval, working

  @MainActor
  init?(_ session: SessionItem?) {
    guard let session else { return nil }
    if session.awaitingUserSince != nil {
      self = .approval
    } else if MacSessionStatus.busy(session.status) {
      self = .working
    } else {
      return nil
    }
  }
}
