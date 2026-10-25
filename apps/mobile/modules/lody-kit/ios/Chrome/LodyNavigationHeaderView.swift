import ExpoModulesCore
import UIKit

final class LodyNavigationHeaderView: ExpoView {
  let onAction = EventDispatcher()
  let onSearch = EventDispatcher()
  private weak var header: LodyNavigationHeader?
  private weak var owner: UIViewController?
  private var itemsJSON = ""
  private var leftItemsJSON = ""
  private var toolbarJSON = ""
  private var searchJSON = ""
  private var title = ""
  private var rightItems: [UIBarButtonItem] = []
  private var leftItems: [UIBarButtonItem] = []
  private var toolbarItems: [UIBarButtonItem] = []
  private var toolbarDirty = false
  private var ownsToolbar = false
  private var waitingForTransition = false
  private var search: LodyNavigationSearch?
  private var mounted: [UIView] = []
  private var slots: [Int: LodyBarSlot] = [:]
  private var pushedRight: [UIBarButtonItem]?
  private var pushedLeft: [UIBarButtonItem]?
  private var pushedTitle: String?
  private var pushedSearch: LodyNavigationSearch?

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    isUserInteractionEnabled = false
    isAccessibilityElement = false
    accessibilityElementsHidden = true
  }

  func setItems(_ json: String) {
    guard json != itemsJSON else { return }
    itemsJSON = json
    decodeRight()
    push()
  }

  func setLeftItems(_ json: String) {
    guard json != leftItemsJSON else { return }
    leftItemsJSON = json
    decodeLeft()
    push()
  }

  func setTitle(_ value: String) {
    guard value != title else { return }
    title = value
    push()
  }

  func setToolbarItems(_ json: String) {
    guard json != toolbarJSON else { return }
    toolbarJSON = json
    if !json.isEmpty { ownsToolbar = true }
    toolbarDirty = true
    pushToolbar()
  }

  func setSearch(_ json: String) {
    guard json != searchJSON else { return }
    searchJSON = json
    if let config = try? JSONDecoder().decode(LodyNavigationSearch.Config.self, from: Data(json.utf8)) {
      let next = search ?? LodyNavigationSearch()
      next.emit = { [weak self] type, text in self?.onSearch(["type": type, "text": text]) }
      next.configure(config)
      search = next
    } else {
      search = nil
    }
    push()
    toolbarDirty = true
    pushToolbar()
  }

  func setSearchCommand(_ json: String) {
    guard let command = try? JSONDecoder().decode(LodyNavigationSearch.Command.self, from: Data(json.utf8)) else { return }
    search?.perform(command)
  }

  override func mountChildComponentView(_ childComponentView: UIView, index: Int) {
    mounted.insert(childComponentView, at: min(index, mounted.count))
    slotsChanged()
  }

  override func unmountChildComponentView(_ childComponentView: UIView, index: Int) {
    mounted.removeAll { $0 === childComponentView }
    childComponentView.removeFromSuperview()
    slotsChanged()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil else { return }
    if header == nil {
      var responder = next
      while let current = responder {
        if let controller = current as? UIViewController {
          owner = controller
          header = LodyNavigationHeader.of(controller.navigationItem)
          break
        }
        responder = current.next
      }
    }
    push()
    pushToolbar()
  }

  override func willMove(toSuperview newSuperview: UIView?) {
    if newSuperview == nil { release() }
    super.willMove(toSuperview: newSuperview)
  }

  private func slotsChanged() {
    decodeRight()
    decodeLeft()
    push()
    toolbarDirty = true
    pushToolbar()
  }

  private func decodeRight() {
    // UIKit lays rightBarButtonItems out right-to-left; specs read left-to-right.
    rightItems = decode(itemsJSON).reversed()
  }

  private func decodeLeft() {
    leftItems = decode(leftItemsJSON)
  }

  private func decode(_ json: String) -> [UIBarButtonItem] {
    var slots = LodyNavigationHeaderItems.Slots()
    slots.view = { [weak self] index, size in self?.slot(index, size: size) }
    slots.search = { [weak self] in
      guard let self, self.search != nil else { return nil }
      return self.owner?.navigationItem.searchBarPlacementBarButtonItem
    }
    return LodyNavigationHeaderItems.decode(json, slots: slots) { [weak self] id in self?.onAction(["id": id]) }
  }

  private func slot(_ index: Int, size: CGSize) -> UIView? {
    guard mounted.indices.contains(index) else { return nil }
    let container = slots[index] ?? LodyBarSlot()
    slots[index] = container
    container.host(mounted[index], size: size)
    return container
  }

  private func push() {
    guard header != nil else { return }
    claim(\.rightItems, itemsJSON.isEmpty ? nil : rightItems, &pushedRight)
    claim(\.leftItems, leftItemsJSON.isEmpty ? nil : leftItems, &pushedLeft)
    claim(\.title, title.isEmpty ? nil : title, &pushedTitle)
    claim(\.search, search, &pushedSearch)
    header?.refresh()
  }

  // Several headers can share one navigation item; each clears only what it last wrote.
  private func claim<Value: Equatable>(
    _ slot: ReferenceWritableKeyPath<LodyNavigationHeader, Value?>,
    _ value: Value?,
    _ pushed: inout Value?
  ) {
    guard let header else { return }
    if let value {
      if header[keyPath: slot] != value { header[keyPath: slot] = value }
    } else if let previous = pushed, header[keyPath: slot] == previous {
      header[keyPath: slot] = nil
    }
    pushed = value
  }

  private func pushToolbar() {
    guard ownsToolbar, let owner else { return }
    // Even a nonanimated item update can replace UIKit's retiring glass.
    // Keep the existing items throughout push/pop, including cancellation.
    if let transition = owner.navigationController?.transitionCoordinator {
      guard !waitingForTransition else { return }
      waitingForTransition = true
      transition.animate(alongsideTransition: nil) { [weak self] _ in
        self?.waitingForTransition = false
        self?.pushToolbar()
      }
      return
    }
    if toolbarDirty {
      toolbarDirty = false
      toolbarItems = decode(toolbarJSON)
      for item in toolbarItems where item.menu != nil { item.preferredMenuElementOrder = .fixed }
    }
    let items = toolbarJSON.isEmpty ? [] : toolbarItems
    if owner.toolbarItems ?? [] != items { owner.setToolbarItems(items.isEmpty ? nil : items, animated: false) }
    // The navigation stack owns visibility during transitions; offscreen
    // updates must not bring the shared toolbar over the current page.
    if let navigation = owner.navigationController, navigation.topViewController === owner {
      navigation.setToolbarHidden(items.isEmpty, animated: false)
    }
  }

  private func release() {
    claim(\.rightItems, nil, &pushedRight)
    claim(\.leftItems, nil, &pushedLeft)
    claim(\.title, nil, &pushedTitle)
    claim(\.search, nil, &pushedSearch)
    if ownsToolbar, let owner, !toolbarItems.isEmpty, owner.toolbarItems ?? [] == toolbarItems {
      owner.setToolbarItems(nil, animated: false)
      if let navigation = owner.navigationController, navigation.topViewController === owner {
        navigation.setToolbarHidden(true, animated: false)
      }
    }
    header = nil
    owner = nil
  }
}

private final class LodyBarSlot: UIView {
  private var width: NSLayoutConstraint?
  private var height: NSLayoutConstraint?

  init() {
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
  }

  required init?(coder: NSCoder) { nil }

  // UIKit sizes the bar slot; Fabric still writes the content's React origin.
  override func layoutSubviews() {
    super.layoutSubviews()
    subviews.first?.center = CGPoint(x: bounds.midX, y: bounds.midY)
  }

  func host(_ content: UIView, size: CGSize) {
    if content.superview !== self {
      subviews.forEach { $0.removeFromSuperview() }
      addSubview(content)
    }
    if let width, let height {
      width.constant = size.width
      height.constant = size.height
      return
    }
    let width = widthAnchor.constraint(equalToConstant: size.width)
    let height = heightAnchor.constraint(equalToConstant: size.height)
    NSLayoutConstraint.activate([width, height])
    self.width = width
    self.height = height
  }
}
