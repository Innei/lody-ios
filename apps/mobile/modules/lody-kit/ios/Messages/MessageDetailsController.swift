import UIKit

@MainActor
final class MessageDetailsController: UIViewController {
  let entryId: String
  private var entry: ChatEntry?
  private let list = LodyGroupedList(appContext: nil)

  init(entryId: String, entry: ChatEntry?) {
    self.entryId = entryId
    self.entry = entry
    super.init(nibName: nil, bundle: nil)
    title = LodyStrings.text("message.details.title")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    list.frame = view.bounds
    list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    list.setTransparent(true)
    list.setPlaceholder(LodyStrings.text("message.details.empty"))
    view.addSubview(list)
    render()
  }

  override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    parent?.navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: LodyStrings.text("common.done"), primaryAction: UIAction { [weak self] _ in
        guard let self else { return }
        LodyShell.shared.finish(from: self, value: nil)
        LodyShell.shared.close(from: self)
      }
    )
  }

  // The owning chat supplies its accepted projection; this page never watches the runtime.
  func update(_ entry: ChatEntry?) {
    self.entry = entry
    if isViewLoaded { render() }
  }

  private func render() {
    let name = entry?.modelInfo?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    list.setSections(MessageDetailsSections.make(
      model: name.isEmpty ? entry?.modelInfo?.modelId : name,
      reasoning: entry?.modelInfo?.thoughtLevel, input: entry?.inputConfig, usage: entry?.tokenUsage
    ))
  }
}
