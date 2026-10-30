import LodyCore
import UIKit

@MainActor
final class CreateChoiceController: CreateListController {
  private let header: String
  private let placeholder: String
  private let options: [(id: String, title: String, subtitle: String)]
  private let selected: String?
  private let onPick: (String) -> Void

  init(
    title: String, header: String, placeholder: String,
    options: [(id: String, title: String, subtitle: String)], selected: String?, onPick: @escaping (String) -> Void
  ) {
    self.header = header
    self.placeholder = placeholder
    self.options = options
    self.selected = selected
    self.onPick = onPick
    super.init(nibName: nil, bundle: nil)
    self.title = title
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    list.setPlaceholder(placeholder)
    list.setSections(CreateSessionSections.choices(options, header: header, selected: selected))
  }

  override func event(_ name: String, _ body: [String: Any]) {
    guard name == "rowPress", let id = body["id"] as? String else { return }
    onPick(id)
    navigationController?.popViewController(animated: true)
  }
}
