import UIKit

@MainActor
class FormController: UIViewController {
  let scroll = UIScrollView()
  let stack = UIStackView()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .lodyGround
    scroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.contentInsetAdjustmentBehavior = .automatic
    scroll.keyboardDismissMode = .interactive
    scroll.delaysContentTouches = false
    scroll.alwaysBounceVertical = true
    LodyScrollEdges.navigation(scroll)
    view.addSubview(scroll)
    stack.axis = .vertical
    stack.spacing = LodyDesign.Rail.groupGap
    stack.translatesAutoresizingMaskIntoConstraints = false
    scroll.addSubview(stack)
    NSLayoutConstraint.activate([
      scroll.topAnchor.constraint(equalTo: view.topAnchor),
      scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
      stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
      stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
      stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
    ])
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    LodyScrollEdges.bind(scroll, to: self)
  }

  var header: UINavigationItem? { parent?.navigationItem }

  func closeForm() {
    view.endEditing(true)
    dismiss(animated: true)
  }

  static func barButton(
    title: String? = nil, symbol: String? = nil, label: String, prominent: Bool = false,
    action: @escaping @MainActor () -> Void
  ) -> UIBarButtonItem {
    let item = UIBarButtonItem(primaryAction: UIAction(title: title ?? "", image: symbol.flatMap { UIImage(systemName: $0) }) { _ in
      action()
    })
    item.accessibilityLabel = label
    if prominent {
      item.style = .prominent
      item.tintColor = .lodyAccent
    }
    return item
  }
}
