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
  private let workspace = LodyMenuButton(frame: .zero)
  private let settings = LodySymbolButton(frame: .zero)
  private let search = LodyNavigationSearch()
  private lazy var workspaceSlot = InboxBarSlot(workspace)
  private lazy var settingsSlot = InboxBarSlot(settings)
  private var workspaceItem: UIBarButtonItem?
  private var settingsItem: UIBarButtonItem?
  private var filterItem: UIBarButtonItem?
  private var toolbar: [UIBarButtonItem] = []
  private var toolbarRegular: Bool?
  private var naturalWidth: CGFloat = 44
  private var waitingForTransition = false

  init() {
    workspace.accessibilityIdentifier = "workspace-menu"
    workspace.selected = { [weak self] id in self?.selected(id) }
    workspace.sized = { [weak self] width in
      self?.naturalWidth = width
      self?.layout()
    }
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
    let left = [workspaceItem ?? UIBarButtonItem(customView: workspaceSlot)]
    let filter = filterItem ?? UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease"), menu: nil)
    filter.tintColor = .label
    filter.accessibilityLabel = LodyStrings.text("inbox.settings.section.view")
    filter.menu = filterMenu(mode: model.mode, sort: model.sort)
    let right = [settingsItem ?? UIBarButtonItem(customView: settingsSlot), filter]
    (workspaceItem, settingsItem, filterItem) = (left[0], right[0], filter)
    if header.leftItems != left { header.leftItems = left }
    let regular = host.traitCollection.horizontalSizeClass == .regular
    let headerItems = regular ? [] : right
    if header.rightItems != headerItems { header.rightItems = headerItems }
    let placement = regular ? "stacked" : "integrated"
    if search.config.placement != placement {
      search.configure(.init(placeholder: LodyStrings.text("search.field.placeholder"), placement: placement,
        hideWhenScrolling: false, obscureBackground: false, hideNavigationBar: false))
      header.search = search
    }
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
    let regular = host.traitCollection.horizontalSizeClass == .regular
    if toolbar.isEmpty || toolbarRegular != regular {
      toolbarRegular = regular
      let create = UIBarButtonItem(primaryAction: UIAction(image: UIImage(systemName: "plus")) { [weak self] _ in
        self?.newSession?()
      })
      create.sharesBackground = false
      create.tintColor = .lodyAccent
      create.accessibilityLabel = LodyStrings.text("tabs.newSession")
      if regular, let filterItem, let settingsItem {
        toolbar = [filterItem, settingsItem, .flexibleSpace(), create]
      } else { toolbar = [host.navigationItem.searchBarPlacementBarButtonItem, .fixedSpace(6), create] }
    }
    if host.toolbarItems ?? [] != toolbar { host.setToolbarItems(toolbar, animated: false) }
    if let navigation = host.navigationController, navigation.topViewController === host {
      navigation.setToolbarHidden(false, animated: false)
    }
  }

  func layout() {
    guard let host else { return }
    let insets = host.view.safeAreaInsets
    // Reserve the split view toggle and UIKit glass margins in the sidebar.
    let trailing: CGFloat = host.traitCollection.horizontalSizeClass == .regular ? 160 : 192
    let limit = max(44, host.view.bounds.width - insets.left - insets.right - trailing)
    workspaceSlot.size = CGSize(width: min(naturalWidth, limit), height: 44)
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

// UIKit sizes bar custom views to the bar's height; the control keeps its 44 pt target and overflows the slot.
private final class InboxBarSlot: UIView {
  private let content: UIView
  private var width: NSLayoutConstraint!
  private var height: NSLayoutConstraint!
  var size = CGSize(width: 44, height: 44) {
    didSet {
      width.constant = size.width
      height.constant = size.height
      setNeedsLayout()
    }
  }

  init(_ content: UIView) {
    self.content = content
    super.init(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
    translatesAutoresizingMaskIntoConstraints = false
    addSubview(content)
    width = widthAnchor.constraint(equalToConstant: 44)
    height = heightAnchor.constraint(equalToConstant: 44)
    NSLayoutConstraint.activate([width, height])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func layoutSubviews() {
    super.layoutSubviews()
    content.bounds = CGRect(origin: .zero, size: size)
    content.center = CGPoint(x: bounds.midX, y: bounds.midY)
  }
}
