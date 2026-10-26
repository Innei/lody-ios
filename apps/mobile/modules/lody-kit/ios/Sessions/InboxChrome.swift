import UIKit

@MainActor
final class InboxChrome {
  struct Model {
    var workspaces: [AuthWorkspace]
    var selected: AuthWorkspace?
    var devices: InboxDevices
    var mode: Int
    var sort: InboxSort
  }

  var selectWorkspace: ((String) -> Void)?
  var editWorkspace: (() -> Void)?
  var setView: ((Int) -> Void)?
  var setSort: ((InboxSort) -> Void)?
  var openSettings: (() -> Void)?
  var openDebug: (() -> Void)?
  var newSession: (() -> Void)?
  var searchChanged: ((String) -> Void)?

  static let editId = "workspace:edit"
  private static let views = [
    (mode: 0, key: "inbox.settings.view.projects", icon: "folder"),
    (mode: 1, key: "inbox.settings.view.activity", icon: "clock"),
    (mode: 2, key: "inbox.settings.view.chat", icon: "bubble.left"),
  ]
  private static let sorts: [(sort: InboxSort, icon: String)] = [
    (.name, "textformat"), (.activity, "clock"), (.urgency, "exclamationmark.circle"),
  ]

  private weak var host: UIViewController?
  private var header: LodyNavigationHeader?
  private let workspace = LodyMenuButton(appContext: nil)
  private let settings = LodySymbolButton(appContext: nil)
  private let search = LodyNavigationSearch()
  private var workspaceWidth: NSLayoutConstraint?
  private var workspaceItem: UIBarButtonItem?
  private var settingsItem: UIBarButtonItem?
  private var filterItem: UIBarButtonItem?
  private var toolbar: [UIBarButtonItem] = []
  private var naturalWidth: CGFloat = 44
  private var waitingForTransition = false

  init() {
    workspace.accessibilityIdentifier = "workspace-menu"
    workspace.translatesAutoresizingMaskIntoConstraints = false
    workspace.heightAnchor.constraint(equalToConstant: 44).isActive = true
    workspaceWidth = workspace.widthAnchor.constraint(equalToConstant: 44)
    workspaceWidth?.isActive = true
    workspace.selected = { [weak self] id in self?.selected(id) }
    workspace.sized = { [weak self] width in
      self?.naturalWidth = width
      self?.layout()
    }
    settings.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      settings.widthAnchor.constraint(equalToConstant: 44), settings.heightAnchor.constraint(equalToConstant: 44),
    ])
    settings.setSymbol("gearshape")
    settings.setAccessibilityName(LodyStrings.text("tabs.settings"))
    settings.setLongPress(true)
    settings.pressed = { [weak self] in self?.openSettings?() }
    settings.held = { [weak self] in self?.openDebug?() }
    search.configure(LodyNavigationSearch.Config(
      placeholder: LodyStrings.text("search.field.placeholder"), placement: "integrated", hideWhenScrolling: false
    ))
    search.emit = { [weak self] event, text in
      if event == "change" { self?.searchChanged?(text) }
    }
  }

  func attach(to host: UIViewController) {
    self.host = host
    header = LodyNavigationHeader.of(host.navigationItem)
  }

  func update(_ model: Model?) {
    guard let host, let header else { return }
    guard let model else {
      clear()
      return
    }
    let name = model.selected?.name ?? LodyStrings.text("common.workspace")
    workspace.setAccessibilityName(
      "\(LodyStrings.text("inbox.workspaceSwitch.accessibility", ["name": name])), \(model.devices.summary)"
    )
    var avatar = LodyMenuAvatar()
    avatar.text = String(name.prefix(1))
    avatar.color = LodyAccentChoice.hex(UIColor.lodyAccent.resolvedColor(with: host.traitCollection))
    avatar.image = model.selected?.image ?? ""
    workspace.setAvatar(avatar)
    workspace.setLabel(name)
    workspace.setStatus(model.devices.status)
    workspace.setItems(menuItems(model))
    layout()
    let left = [workspaceItem ?? UIBarButtonItem(customView: workspace)]
    let filter = filterItem ?? UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease"), menu: nil)
    filter.tintColor = .label
    filter.accessibilityLabel = LodyStrings.text("inbox.settings.section.view")
    filter.menu = filterMenu(mode: model.mode, sort: model.sort)
    let right = [settingsItem ?? UIBarButtonItem(customView: settings), filter]
    (workspaceItem, settingsItem, filterItem) = (left[0], right[0], filter)
    if header.leftItems != left { header.leftItems = left }
    if header.rightItems != right { header.rightItems = right }
    if header.search !== search { header.search = search }
    showToolbar()
  }

  func detach() {
    clear()
    header = nil
    host = nil
  }

  private func clear() {
    guard let header else { return }
    if let item = workspaceItem, header.leftItems == [item] { header.leftItems = nil }
    if let settingsItem, let filterItem, header.rightItems == [settingsItem, filterItem] { header.rightItems = nil }
    if header.search === search { header.search = nil }
    if let host, !toolbar.isEmpty, host.toolbarItems ?? [] == toolbar {
      host.setToolbarItems(nil, animated: false)
      if let navigation = host.navigationController, navigation.topViewController === host {
        navigation.setToolbarHidden(true, animated: false)
      }
    }
  }

  private func showToolbar() {
    guard let host else { return }
    // Even a nonanimated item update can replace UIKit's retiring glass during push/pop.
    if let transition = host.navigationController?.transitionCoordinator {
      guard !waitingForTransition else { return }
      waitingForTransition = true
      transition.animate(alongsideTransition: nil) { [weak self] _ in
        self?.waitingForTransition = false
        self?.showToolbar()
      }
      return
    }
    if toolbar.isEmpty {
      let create = UIBarButtonItem(primaryAction: UIAction(image: UIImage(systemName: "plus")) { [weak self] _ in
        self?.newSession?()
      })
      create.sharesBackground = false
      create.tintColor = .lodyAccent
      create.accessibilityLabel = LodyStrings.text("tabs.newSession")
      toolbar = [host.navigationItem.searchBarPlacementBarButtonItem, .fixedSpace(6), create]
    }
    if host.toolbarItems ?? [] != toolbar { host.setToolbarItems(toolbar, animated: false) }
    if let navigation = host.navigationController, navigation.topViewController === host {
      navigation.setToolbarHidden(false, animated: false)
    }
  }

  func layout() {
    guard let host else { return }
    let insets = host.view.safeAreaInsets
    // Leave room for both trailing actions and UIKit's glass group margins.
    let limit = max(44, host.view.bounds.width - insets.left - insets.right - 192)
    workspaceWidth?.constant = min(naturalWidth, limit)
  }

  private func menuItems(_ model: Model) -> [LodyMenuItem] {
    var items = [model.devices.menu]
    items += model.workspaces.map { workspace in
      var item = LodyMenuItem()
      item.id = workspace.id
      item.title = workspace.name
      item.selected = workspace.id == model.selected?.id
      return item
    }
    if model.selected != nil {
      var edit = LodyMenuItem()
      edit.id = Self.editId
      edit.title = LodyStrings.text("workspace.edit.action")
      items.append(edit)
    }
    return items
  }

  private func selected(_ id: String) {
    if id == Self.editId {
      editWorkspace?()
    } else if !id.hasPrefix("__device") {
      selectWorkspace?(id)
    }
  }

  private func filterMenu(mode: Int, sort: InboxSort) -> UIMenu {
    let views = Self.views.map { view in
      UIAction(title: LodyStrings.text(view.key), image: UIImage(systemName: view.icon), state: mode == view.mode ? .on : .off) {
        [weak self] _ in self?.setView?(view.mode)
      }
    }
    let sorts = Self.sorts.map { item in
      UIAction(
        title: LodyStrings.text("inbox.settings.sort.\(item.sort.rawValue)"), image: UIImage(systemName: item.icon),
        state: sort == item.sort ? .on : .off
      ) { [weak self] _ in self?.setSort?(item.sort) }
    }
    return UIMenu(children: views + [UIMenu(options: .displayInline, children: sorts)])
  }
}
