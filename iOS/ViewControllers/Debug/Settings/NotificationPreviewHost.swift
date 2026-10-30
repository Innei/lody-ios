import LodyCore
import UIKit

@MainActor
class NotificationPreviewHost: UIViewController {
  let header = UIStackView()
  private(set) var content: NotificationSettingsController?

  var service: NotificationService { .live }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    header.axis = .vertical
    header.alignment = .leading
    header.spacing = 8
    header.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(header)
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
    ])
    mount()
  }

  func mount() {
    content.map { old in
      old.willMove(toParent: nil)
      old.view.removeFromSuperview()
      old.removeFromParent()
    }
    let next = NotificationSettingsController(service: service, signedIn: { true })
    addChild(next)
    next.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(next.view)
    NSLayoutConstraint.activate([
      next.view.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
      next.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      next.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      next.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    next.didMove(toParent: self)
    content = next
  }

  static func label(_ id: String?, _ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.textColor = .label
    label.font = .preferredFont(forTextStyle: .body)
    label.accessibilityIdentifier = id
    return label
  }

  static func button(_ id: String, _ title: String, _ action: @escaping @MainActor () -> Void) -> UIButton {
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
    button.accessibilityIdentifier = id
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    return button
  }
}
