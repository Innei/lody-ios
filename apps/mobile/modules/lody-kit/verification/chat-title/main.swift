import UIKit

func texts(_ view: UIView) -> [String] {
  var result: [String] = []
  if let label = view as? UILabel, let text = label.text, !text.isEmpty {
    result.append(text)
  }
  if let button = view as? UIButton {
    if let title = button.configuration?.title, !title.isEmpty { result.append(title) }
    if let subtitle = button.configuration?.subtitle, !subtitle.isEmpty { result.append(subtitle) }
    if let attributed = button.configuration?.attributedSubtitle {
      let string = String(attributed.characters)
      if !string.isEmpty { result.append(string) }
    }
    if let label = button.titleLabel?.text, !label.isEmpty { result.append(label) }
  }
  for subview in view.subviews { result += texts(subview) }
  return result
}

func containsText(_ view: UIView, _ needle: String) -> Bool {
  texts(view).contains { $0.contains(needle) }
}

func subtitleText(_ button: UIButton) -> String {
  if let titleButton = button as? ChatNavigationTitleButton {
    return titleButton.captionLabel.attributedText?.string ?? ""
  }
  if let attributed = button.configuration?.attributedSubtitle {
    return String(attributed.characters)
  }
  return button.configuration?.subtitle ?? ""
}

func subtitleAttachments(_ button: UIButton) -> Int {
  let ns: NSAttributedString?
  if let titleButton = button as? ChatNavigationTitleButton {
    ns = titleButton.captionLabel.attributedText
  } else if let attributed = button.configuration?.attributedSubtitle {
    ns = NSAttributedString(attributed)
  } else {
    ns = nil
  }
  guard let ns else { return 0 }
  var count = 0
  ns.enumerateAttribute(.attachment, in: NSRange(location: 0, length: ns.length)) { value, _, _ in
    if value is NSTextAttachment { count += 1 }
  }
  return count
}

func titleSnapshot(_ host: UIView) -> Data {
  let size = CGSize(width: max(1, host.bounds.width), height: max(1, host.bounds.height))
  return UIGraphicsImageRenderer(size: size).image { context in
    UIColor.white.setFill()
    context.fill(CGRect(origin: .zero, size: size))
    host.layer.render(in: context.cgContext)
  }.pngData()!
}

precondition(
  ChatNavigationTitle.plainSubtitle(project: "Project name", machine: "Studio") == "Project name · Studio",
  "Plain subtitle joins project and computer names"
)
precondition(
  ChatNavigationTitle.plainSubtitle(project: "Project name", machine: "") == "Project name",
  "A missing computer name must not leave a dangling separator"
)

let button = ChatNavigationTitleButton()
button.accessibilityIdentifier = "chat-navigation-title"
ChatNavigationTitle.configureButton(button, title: "Session title", subtitle: "Project name", machine: "Studio")
precondition(button.displayedTitle == "Session title", "First line shows the session title")
precondition(button.configuration?.title == nil, "First line must not be a static configuration title")
precondition(button.titleHost.superview === button, "First line renders through the numeric-text host")
let item = UINavigationItem(title: "Session title")
ChatNavigationTitle.apply(title: "Session title", subtitle: "Project name · Studio", button: button, to: item)

precondition(item.style == .browser, "Browser style keeps the two-line title")
precondition(item.titleView === button, "Title stays tappable")
precondition(subtitleText(button).contains("Project name"), "Settled titleView shows the project name")
precondition(subtitleText(button).contains("Studio"), "Settled titleView shows the computer name")
precondition(subtitleAttachments(button) == 2, "Subtitle must show folder and computer symbols")
precondition(button.accessibilityLabel?.contains("Project name") == true)
precondition(button.accessibilityLabel?.contains("Studio") == true)
precondition(button.accessibilityLabel?.contains("m1") != true, "The title must not speak a machine id")

let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
let root = UIViewController()
root.title = "Inbox"
let nav = UINavigationController(rootViewController: root)
let session = UIViewController()
session.view.backgroundColor = .systemBackground
ChatNavigationTitle.configureButton(button, title: "Session title", subtitle: "Project name", machine: "Studio")
ChatNavigationTitle.apply(title: "Session title", subtitle: "Project name · Studio", button: button, to: session.navigationItem)
nav.pushViewController(session, animated: false)
window.rootViewController = nav
window.makeKeyAndVisible()
nav.view.setNeedsLayout()
nav.view.layoutIfNeeded()
session.view.layoutIfNeeded()

precondition(containsText(nav.navigationBar, "Project name"), "Nav bar must show the project name")
precondition(containsText(nav.navigationBar, "Studio"), "Nav bar must show the computer name")
precondition(subtitleAttachments(button) == 2, "Folder and computer symbols must survive layout")

ChatNavigationTitle.preserveSubtitle("Project name · Studio", on: session.navigationItem)
session.navigationItem.titleView = nil
session.navigationItem.title = "Session title"
nav.view.setNeedsLayout()
nav.view.layoutIfNeeded()
precondition(
  session.navigationItem.subtitle == "Project name · Studio",
  "A screens header update that nils titleView must keep UINavigationItem.subtitle"
)
precondition(
  containsText(nav.navigationBar, "Project name"),
  "Project name must stay visible after titleView is cleared"
)
precondition(
  containsText(nav.navigationBar, "Studio"),
  "Computer name must stay visible after titleView is cleared"
)

ChatNavigationTitle.detach(button: button, from: session.navigationItem)
precondition(session.navigationItem.titleView !== button)
precondition(session.navigationItem.subtitle == "Project name · Studio", "Detach must not clear the native subtitle")
ChatNavigationTitle.apply(title: "Session title", subtitle: "Project name · Studio", button: button, to: session.navigationItem)
precondition(session.navigationItem.titleView === button, "Cancelled return must restore the tappable title")
precondition(session.navigationItem.subtitle == nil, "Restoring titleView must drop the native subtitle so the button stays visible")

// A full-screen preview preserves the fallback without removing our titleView.
ChatNavigationTitle.preserveSubtitle("Project name · Studio", on: session.navigationItem)
ChatNavigationTitle.apply(title: "Session title", subtitle: "Project name · Studio", button: button, to: session.navigationItem)
nav.view.layoutIfNeeded()
precondition(session.navigationItem.subtitle == nil, "Preview return must not show a second subtitle alongside the retained titleView")
precondition(session.navigationItem.titleView === button)

button.layoutIfNeeded()
let settled = titleSnapshot(button.titleHost)
ChatNavigationTitle.configureButton(button, title: "Brand new heading", subtitle: "Project name", machine: "Studio")
nav.view.layoutIfNeeded()
session.view.layoutIfNeeded()
button.layoutIfNeeded()
var frames: [Data] = []
for _ in 0..<8 {
  RunLoop.main.run(until: Date().addingTimeInterval(0.05))
  frames.append(titleSnapshot(button.titleHost))
}
precondition(button.displayedTitle == "Brand new heading", "Title updates keep the numeric-text host in sync")
if !UIAccessibility.isReduceMotionEnabled {
  precondition(frames.contains { $0 != settled }, "Changing the first line must run a numeric text transition")
}

print("PASS: chat navigation subtitle shows project and computer names")
