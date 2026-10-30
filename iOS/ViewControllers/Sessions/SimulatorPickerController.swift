import LodyCore
import UIKit

@MainActor
final class SimulatorPickerController: UIViewController {
  private let store: SessionSimulator
  private let selected: (SessionSimulator.Device) -> Void
  private let list = LodyGroupedList(frame: .zero)
  private var devices: [SessionSimulator.Device] = []
  private var error = ""
  private var task: Task<Void, Never>?
  init(store: SessionSimulator, selected: @escaping (SessionSimulator.Device) -> Void) {
    self.store = store; self.selected = selected; super.init(nibName: nil, bundle: nil)
  }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }
  isolated deinit { task?.cancel() }
  override func viewDidLoad() {
    super.viewDidLoad()
    SettingsPage.host(list, in: self) { [weak self] name, body in
      guard name == "rowPress", let self, let id = body["id"] as? String else { return }
      if id == "retry" { load(); return }
      guard let device = devices.first(where: { $0.udid == id }), device.available, device.occupancy != .otherSession else { return }
      navigationController?.dismiss(animated: true) { [selected] in selected(device) }
    }
    load()
  }
  private func load() {
    task?.cancel(); error = ""; list.setLoading(true)
    task = Task { [weak self, store] in
      do {
        let devices = try await store.devices()
        guard !Task.isCancelled, let self else { return }
        self.devices = devices
      } catch {
        guard !Task.isCancelled, let self else { return }
        self.error = error.localizedDescription
      }
      self?.render()
    }
  }
  private func render() {
    list.setLoading(false)
    var sections: [LodyListSection] = []
    if !error.isEmpty {
      var section = LodyListSection(); section.id = "error"; section.footer = error
      var retry = LodyListRow(); retry.id = "retry"; retry.title = String(localized: "common.retry", bundle: .lody); retry.action = true
      section.rows = [retry]; sections.append(section)
    }
    for key in ["booted", "shutdown", "unavailable"] {
      let group = devices.filter { device in
        if !device.available { return key == "unavailable" }
        return key == (device.state == "Booted" ? "booted" : "shutdown")
      }
      guard !group.isEmpty else { continue }
      var section = LodyListSection(); section.id = key; section.header = String(localized: String.LocalizationValue("simulator.section." + key), bundle: .lody)
      section.rows = group.map { device in
        var row = LodyListRow(); row.id = device.udid; row.title = device.name; row.subtitle = device.runtime
        row.image = device.deviceType.hasPrefix("iPad") ? "ipad" : "iphone"
        row.value = String(localized: String.LocalizationValue(device.state == "Booted" ? "simulator.device.preview" : "simulator.device.boot"), bundle: .lody)
        if device.occupancy == .otherSession { row.value = String(localized: "simulator.device.occupied", bundle: .lody) }
        if !device.available { row.value = device.unavailableReason ?? "" }
        row.action = device.available && device.occupancy != .otherSession
        return row
      }
      sections.append(section)
    }
    list.setSections(sections)
  }
}
