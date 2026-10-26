import Foundation

struct InboxDevices {
  static let menuId = "__devices__"

  let status: String
  let summary: String
  let menu: LodyMenuItem

  init(catalog: SessionCatalog, presence: SettingsMachinePresence) {
    let online = catalog.machineIds.filter { presence.status(of: $0) == "online" }.count
    let live = presence.state == "live"
    if live {
      status = online > 0 ? "online" : "offline"
      summary = LodyStrings.text("devices.summary", ["count": online, "total": catalog.machineIds.count])
    } else {
      status = "unknown"
      summary = LodyStrings.text("devices.unknown")
    }
    var menu = LodyMenuItem()
    menu.id = Self.menuId
    menu.title = LodyStrings.text("devices.title")
    menu.subtitle = summary
    menu.symbol = "desktopcomputer"
    menu.disabled = catalog.machineIds.isEmpty
    menu.children = catalog.machineIds.map { id in
      var item = LodyMenuItem()
      item.id = "__device__\(id)"
      item.title = catalog.machineNames[id] ?? id
      item.subtitle = LodyStrings.text("devices.\(presence.status(of: id))")
      item.disabled = true
      return item
    }
    self.menu = menu
  }
}
