import UIKit

@MainActor
final class SimulatorController: UIViewController {
  private let store: SessionSimulator
  private let simulator = LodySimulatorView(appContext: nil)
  private let notice = UIContentUnavailableView(configuration: .empty())
  private var command = 0

  init(store: SessionSimulator) { self.store = store; super.init(nibName: nil, bundle: nil) }
  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    for child in [simulator, notice] as [UIView] {
      child.frame = view.bounds; child.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(child)
    }
    store.watch(self) { [weak self] in self?.render() }
    render()
  }
  override func didMove(toParent parent: UIViewController?) { super.didMove(toParent: parent); if isViewLoaded { render() } }
  private func render() {
    let source = store.sourceJSON
    simulator.setSource(source); simulator.isHidden = source.isEmpty; notice.isHidden = !source.isEmpty
    if source.isEmpty {
      var configuration = UIContentUnavailableConfiguration.empty()
      configuration.text = store.phaseText
      configuration.secondaryText = store.message
      notice.configuration = configuration
    }
    parent?.navigationItem.title = store.name
    let home = UIBarButtonItem(image: UIImage(systemName: "house"), primaryAction: UIAction { [weak self] _ in self?.run("home") })
    home.accessibilityLabel = LodyStrings.text("simulator.action.home"); home.isEnabled = !source.isEmpty
    let groups = [
      [("app-switcher", "appSwitcher", "square.stack"), ("lock", "lock", "lock")],
      [("rotate-left", "rotateLeft", "rotate.left"), ("rotate-right", "rotateRight", "rotate.right"), ("shake", "shake", "iphone.radiowaves.left.and.right")],
      [("volume-up", "volumeUp", "speaker.plus"), ("volume-down", "volumeDown", "speaker.minus"), ("action", "actionButton", "button.programmable")],
    ]
    var menus: [UIMenuElement] = groups.map { group in
      UIMenu(options: .displayInline, children: group.map { id, key, symbol in
        UIAction(title: LodyStrings.text("simulator.action." + key), image: UIImage(systemName: symbol), attributes: source.isEmpty ? .disabled : []) { [weak self] _ in self?.run(id) }
      })
    }
    menus.append(UIMenu(options: .displayInline, children: [
      UIAction(title: LodyStrings.text("simulator.chooseAnother"), image: UIImage(systemName: "iphone.gen3")) { [weak self] _ in
        guard let self else { return }
        let picker = SimulatorPickerController(store: store) { [weak self] device in self?.store.start(device) }
        LodyShell.shared.presentNative(picker, title: LodyStrings.text("simulator.choose"), grabber: true)
      },
      UIAction(title: LodyStrings.text("simulator.stop"), image: UIImage(systemName: "stop.circle"), attributes: .destructive) { [weak self] _ in self?.stop() },
    ]))
    let menu = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: menus))
    menu.accessibilityLabel = LodyStrings.text("common.more")
    parent?.navigationItem.rightBarButtonItems = [menu, home]
  }
  private func run(_ action: String) {
    command += 1
    simulator.setCommand(SessionController.json(["token": command, "action": action]))
  }
  private func stop() {
    Task { [weak self] in
      guard let self else { return }
      do { try await store.stop(); SettingsPage.pop(self) }
      catch { LodyToastOverlay.shared.show(message: error.localizedDescription, kind: "error") }
    }
  }
}

@MainActor
final class SimulatorPickerController: UIViewController {
  private let store: SessionSimulator
  private let selected: (SessionSimulator.Device) -> Void
  private let list = LodyGroupedList(appContext: nil)
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
      let section = LodyListSection(); section.id = "error"; section.footer = error
      let retry = LodyListRow(); retry.id = "retry"; retry.title = LodyStrings.text("common.retry"); retry.action = true
      section.rows = [retry]; sections.append(section)
    }
    for key in ["booted", "shutdown", "unavailable"] {
      let group = devices.filter { device in
        if !device.available { return key == "unavailable" }
        return key == (device.state == "Booted" ? "booted" : "shutdown")
      }
      guard !group.isEmpty else { continue }
      let section = LodyListSection(); section.id = key; section.header = LodyStrings.text("simulator.section." + key)
      section.rows = group.map { device in
        let row = LodyListRow(); row.id = device.udid; row.title = device.name; row.subtitle = device.runtime
        row.image = device.deviceType.hasPrefix("iPad") ? "ipad" : "iphone"
        row.value = LodyStrings.text(device.state == "Booted" ? "simulator.device.preview" : "simulator.device.boot")
        if device.occupancy == .otherSession { row.value = LodyStrings.text("simulator.device.occupied") }
        if !device.available { row.value = device.unavailableReason ?? "" }
        row.action = device.available && device.occupancy != .otherSession
        return row
      }
      sections.append(section)
    }
    list.setSections(sections)
  }
}
