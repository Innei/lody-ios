import Foundation

enum SettingsText {
  static func statusHeader(_ section: inout LodyListSection, name: String, status: String) {
    guard status != "unknown" else {
      section.header = name
      return
    }
    section.header = "\(name) · \(String(localized: String.LocalizationValue("devices." + status), bundle: .lody))"
    section.headerStatus = status
  }

  static func option(_ id: String, _ title: String, symbol: String = "", selected: Bool) -> LodyListAction {
    var action = LodyListAction()
    action.id = id
    action.title = title
    action.symbol = symbol
    action.selected = selected
    return action
  }

  static func footer(_ id: String, _ text: String) -> LodyListSection {
    var section = LodyListSection()
    section.id = id
    section.footer = text
    return section
  }
}
