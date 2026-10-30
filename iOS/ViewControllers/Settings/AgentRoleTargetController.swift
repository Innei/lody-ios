import LodyCore
import UIKit

@MainActor
final class AgentRoleTargetController: UIViewController {
  private let list = LodyGroupedList(frame: .zero)
  private let agents: [AgentRoleAgent]
  private let picked: (AgentRoleAgent) -> Void

  init(agents: [AgentRoleAgent], picked: @escaping (AgentRoleAgent) -> Void) {
    self.agents = agents
    self.picked = picked
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    list.frame = view.bounds
    list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    list.forwarded = { [weak self] name, body in
      guard name == "rowPress", let self, let index = (body["id"] as? String).flatMap(Int.init),
            self.agents.indices.contains(index) else { return }
      self.picked(self.agents[index])
      self.navigationController?.popViewController(animated: true)
    }
    view.addSubview(list)
    var section = LodyListSection()
    section.id = "agents"
    section.rows = agents.enumerated().map { index, agent in
      var row = LodyListRow()
      row.id = String(index)
      row.title = agent.name
      row.subtitle = agent.machineName
      row.action = true
      return row
    }
    list.setSections([section])
  }
}
