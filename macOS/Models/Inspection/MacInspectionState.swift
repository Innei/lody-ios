import Foundation

enum MacInspectionTarget: Hashable {
  case file(String)
  case attachment(id: String, session: String, name: String)

  var name: String {
    switch self {
    case .file(let path): (path as NSString).lastPathComponent
    case .attachment(_, _, let name): name
    }
  }
  var path: String {
    switch self {
    case .file(let path): path
    case .attachment(_, _, let name): name
    }
  }
}

struct MacInspectionState {
  enum Selection: Equatable { case changes, document(MacInspectionTarget) }
  struct Tab {
    var target: MacInspectionTarget
    var pinned: Bool
    var scrollX = 0.0
    var scrollY = 0.0
    var wrap = false
  }
  var tabs: [Tab] = []
  var selection: Selection = .changes
  var isOpen = false

  mutating func show(_ target: MacInspectionTarget, pinned: Bool = false) {
    if let index = tabs.firstIndex(where: { $0.target == target }) {
      if pinned { tabs[index].pinned = true }
    } else {
      let tab = Tab(target: target, pinned: pinned)
      if let index = tabs.firstIndex(where: { !$0.pinned }) { tabs[index] = tab }
      else { tabs.append(tab) }
    }
    selection = .document(target)
    isOpen = true
  }

  mutating func pin(_ target: MacInspectionTarget) {
    guard let index = tabs.firstIndex(where: { $0.target == target }) else { return }
    tabs[index].pinned = true
  }

  mutating func close(_ target: MacInspectionTarget) {
    guard let index = tabs.firstIndex(where: { $0.target == target }) else { return }
    tabs.remove(at: index)
    guard selection == .document(target) else { return }
    if index > 0 { selection = .document(tabs[index - 1].target) }
    else { selection = .changes }
  }

  mutating func updateReading(_ target: MacInspectionTarget, x: Double, y: Double, wrap: Bool) {
    guard let index = tabs.firstIndex(where: { $0.target == target }) else { return }
    tabs[index].scrollX = x; tabs[index].scrollY = y; tabs[index].wrap = wrap
  }
}

struct MacInspectionLayout {
  struct Placement {
    var sidebarHidden: Bool
    var chatHidden: Bool
    var panelWidth: Double
  }
  var userSidebarHidden = false
  var preferredWidth: Double?
  var isOpen = false
  var expanded = false

  func resolve(width: Double, sidebarWidth: Double = 320) -> Placement {
    guard isOpen else { return Placement(sidebarHidden: userSidebarHidden, chatHidden: false, panelWidth: 0) }
    if expanded { return Placement(sidebarHidden: true, chatHidden: true, panelWidth: width) }
    let desired = preferredWidth ?? (width >= 1382 ? 640 : 620)
    let hidden = userSidebarHidden || width < sidebarWidth + 420 + desired + 2
    let available = width - 420 - 2 - (hidden ? 0 : sidebarWidth)
    return Placement(sidebarHidden: hidden, chatHidden: false, panelWidth: max(320, min(900, desired, available)))
  }
}
