import LodyCore
import UIKit

@MainActor
final class CreateModelController: CreateListController {
  var onChange: ((ModelChoice) -> Void)?
  var choiceForModel: ((String?) -> ModelChoice)?
  private let capability: Capability
  private var choice: ModelChoice
  private var selectedTab = "model"

  init(capability: Capability, choice: ModelChoice) {
    self.capability = capability
    self.choice = choice
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    list.setPlaceholder("")
    render()
  }

  private func render() {
    let tabs = CreateModelOptions.tabs(capability, choice)
    if !tabs.contains(where: { $0.id == selectedTab }) { selectedTab = "model" }
    list.setSegments(tabs.count > 1 ? tabs.map(\.title) : [])
    list.setSelectedSegment(tabs.firstIndex { $0.id == selectedTab } ?? 0)
    list.setSections(CreateModelOptions.sections(capability, choice, tab: selectedTab))
  }

  private func apply(_ next: ModelChoice) {
    choice = next
    onChange?(next)
    render()
  }

  override func event(_ name: String, _ body: [String: Any]) {
    switch name {
    case "segmentChange":
      let tabs = CreateModelOptions.tabs(capability, choice)
      selectedTab = tabs[safe: body["index"] as? Int ?? 0]?.id ?? "model"
      render()
    case "rowToggle":
      guard let id = body["id"] as? String, let on = body["value"] as? Bool else { return }
      apply(CreateModelOptions.toggled(choice, id: id, on: on))
    case "rowPress":
      guard let id = body["id"] as? String else { return }
      if let next = CreateModelOptions.pressed(capability, choice, tab: selectedTab, id: id) {
        apply(next)
      } else {
        let modelId = id == CreateModelOptions.defaultId ? nil : id
        apply(choiceForModel?(modelId) ?? ModelChoice(modelId: modelId))
      }
    default: break
    }
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
