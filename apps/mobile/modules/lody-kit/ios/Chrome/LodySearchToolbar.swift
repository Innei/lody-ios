import ExpoModulesCore
import UIKit

final class LodySearchToolbar: ExpoView, UITextFieldDelegate {
  let onSearchChange = EventDispatcher()
  let onAction = EventDispatcher()

  private let search = UISearchTextField()
  private let glass = UIVisualEffectView(effect: UIGlassContainerEffect())
  private let action = UIButton(configuration: .glass())
  private weak var owner: UIViewController?
  private var visible = true
  private var reservedBottom: CGFloat = 0

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    search.borderStyle = .none
    search.backgroundColor = .clear
    search.accessibilityIdentifier = "ipad-search"
    search.returnKeyType = .search
    search.delegate = self
    search.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
    action.setImage(UIImage(systemName: "plus"), for: .normal)
    action.addTarget(self, action: #selector(pressed), for: .primaryActionTriggered)
    let fieldGlass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    fieldGlass.cornerConfiguration = .capsule()
    fieldGlass.contentView.addSubview(search)
    let stack = UIStackView(arrangedSubviews: [fieldGlass, action])
    stack.spacing = 8
    glass.contentView.addSubview(stack)
    [glass, stack, search].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: glass.contentView.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: glass.contentView.trailingAnchor),
      stack.topAnchor.constraint(equalTo: glass.contentView.topAnchor),
      stack.bottomAnchor.constraint(equalTo: glass.contentView.bottomAnchor),
      action.widthAnchor.constraint(equalToConstant: 48),
      search.leadingAnchor.constraint(equalTo: fieldGlass.contentView.leadingAnchor, constant: 12),
      search.trailingAnchor.constraint(equalTo: fieldGlass.contentView.trailingAnchor, constant: -12),
      search.topAnchor.constraint(equalTo: fieldGlass.contentView.topAnchor),
      search.bottomAnchor.constraint(equalTo: fieldGlass.contentView.bottomAnchor),
    ])
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      detach()
    } else {
      attach()
    }
  }

  func setPlaceholder(_ value: String) {
    search.placeholder = value
  }

  func setActionAccessibilityName(_ value: String) {
    action.accessibilityLabel = value
  }

  func setTint(_ value: String) {
    action.tintColor = lodyTint(value)
  }

  func setVisible(_ value: Bool) {
    visible = value
    updateVisibility()
  }

  @objc private func searchChanged() {
    onSearchChange(["text": search.text ?? ""])
  }

  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    textField.resignFirstResponder()
    return true
  }

  @objc private func pressed() {
    search.resignFirstResponder()
    onAction([:])
  }

  private func attach() {
    guard owner == nil else {
      updateVisibility()
      return
    }
    var responder: UIResponder? = next
    while let current = responder {
      if let controller = current as? UIViewController {
        owner = controller
        let host = controller.navigationController?.view ?? controller.view!
        host.addSubview(glass)
        NSLayoutConstraint.activate([
          glass.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12),
          glass.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -12),
          glass.bottomAnchor.constraint(equalTo: host.keyboardLayoutGuide.topAnchor, constant: -8),
          glass.heightAnchor.constraint(equalToConstant: 48),
        ])
        updateVisibility()
        return
      }
      responder = current.next
    }
  }

  private func updateVisibility() {
    guard let owner else { return }
    glass.isHidden = !visible
    if !visible { search.resignFirstResponder() }
    let next: CGFloat = visible ? 56 : 0
    owner.additionalSafeAreaInsets.bottom += next - reservedBottom
    reservedBottom = next
  }

  private func detach() {
    glass.removeFromSuperview()
    owner?.additionalSafeAreaInsets.bottom -= reservedBottom
    reservedBottom = 0
    self.owner = nil
  }
}
