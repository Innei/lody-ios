import UIKit

func texts(_ view: UIView) -> [String] {
  var result: [String] = []
  if let label = view as? UILabel, let text = label.text, !text.isEmpty {
    result.append(text)
  }
  if let button = view as? UIButton {
    if let title = button.configuration?.title, !title.isEmpty { result.append(title) }
    if let subtitle = button.configuration?.subtitle, !subtitle.isEmpty { result.append(subtitle) }
    if let label = button.titleLabel?.text, !label.isEmpty { result.append(label) }
  }
  for subview in view.subviews { result += texts(subview) }
  return result
}

func containsProject(_ view: UIView) -> Bool {
  texts(view).contains { $0.contains("Project name") }
}

let button = UIButton(type: .system)
button.accessibilityIdentifier = "chat-navigation-title"
ChatNavigationTitle.configureButton(button, title: "Session title", subtitle: "Project name")
let item = UINavigationItem(title: "Session title")
ChatNavigationTitle.apply(title: "Session title", subtitle: "Project name", button: button, to: item)

precondition(item.style == .browser, "Browser style keeps the two-line title")
precondition(item.titleView === button, "Title stays tappable")
precondition(button.configuration?.subtitle == "Project name", "Settled titleView shows the project name")

let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
let root = UIViewController()
root.title = "Inbox"
let nav = UINavigationController(rootViewController: root)
let session = UIViewController()
session.view.backgroundColor = .systemBackground
ChatNavigationTitle.configureButton(button, title: "Session title", subtitle: "Project name")
ChatNavigationTitle.apply(title: "Session title", subtitle: "Project name", button: button, to: session.navigationItem)
nav.pushViewController(session, animated: false)
window.rootViewController = nav
window.makeKeyAndVisible()
nav.view.setNeedsLayout()
nav.view.layoutIfNeeded()
session.view.layoutIfNeeded()

precondition(containsProject(nav.navigationBar), "Nav bar must show the project name")

ChatNavigationTitle.preserveSubtitle("Project name", on: session.navigationItem)
session.navigationItem.titleView = nil
session.navigationItem.title = "Session title"
nav.view.setNeedsLayout()
nav.view.layoutIfNeeded()
precondition(
  session.navigationItem.subtitle == "Project name",
  "A screens header update that nils titleView must keep UINavigationItem.subtitle"
)
precondition(
  containsProject(nav.navigationBar),
  "Project name must stay visible after titleView is cleared"
)

ChatNavigationTitle.detach(button: button, from: session.navigationItem)
precondition(session.navigationItem.titleView !== button)
precondition(session.navigationItem.subtitle == "Project name", "Detach must not clear the native subtitle")
ChatNavigationTitle.clearNativeSubtitle(session.navigationItem)
ChatNavigationTitle.apply(title: "Session title", subtitle: "Project name", button: button, to: session.navigationItem)
precondition(session.navigationItem.titleView === button, "Cancelled return must restore the tappable title")
precondition(session.navigationItem.subtitle == nil, "Restoring titleView must drop the native subtitle so the button stays visible")

print("PASS: chat navigation subtitle survives titleView wipe")
