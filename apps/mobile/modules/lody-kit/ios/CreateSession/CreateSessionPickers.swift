import UIKit

@MainActor
class CreateListController: UIViewController {
  let list = LodyGroupedList(appContext: nil)

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationItem.backButtonDisplayMode = .minimal
    list.frame = view.bounds
    list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    list.setTransparent(true)
    list.forwarded = { [weak self] name, body in self?.event(name, body) }
    view.addSubview(list)
  }

  func event(_ name: String, _ body: [String: Any]) {}
}

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

@MainActor
final class CreateProjectPickerController: CreateListController {
  var onPick: ((CreateProject) -> Void)?
  private let projects: [CreateProject]
  private let machineNames: [String: String]
  private let selectedId: String
  private let loadRepositories: (() async throws -> [CreateProject])?
  private let browse: (() async -> CreateProject?)?
  private var repositories: [CreateProject]?
  private var failed = false
  private var segment: Int
  private var queries = ["", ""]
  private var shown: [String] = []
  private var task: Task<Void, Never>?

  init(
    projects: [CreateProject], machineNames: [String: String], selectedId: String,
    loadRepositories: (() async throws -> [CreateProject])?, browse: (() async -> CreateProject?)?
  ) {
    self.projects = projects
    self.machineNames = machineNames
    self.selectedId = selectedId
    self.loadRepositories = loadRepositories
    self.browse = browse
    segment = CreateProjectPicker.isGithub(selectedId) ? 1 : 0
    super.init(nibName: nil, bundle: nil)
    title = LodyStrings.text("create.row.selectProject")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    if let browse {
      let item = UIBarButtonItem(image: UIImage(systemName: "folder.badge.plus"), primaryAction: UIAction { [weak self] _ in
        Task { [weak self] in
          if let project = await browse() { self?.onPick?(project) }
        }
      })
      item.accessibilityLabel = LodyStrings.text("projectPicker.browse.accessibility")
      navigationItem.rightBarButtonItem = item
    }
    list.setSegments([LodyStrings.text("projectPicker.local"), LodyStrings.text("projectPicker.github")])
    list.setSelectedSegment(segment)
    fetch()
    applySearch()
    render()
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    if isMovingFromParent { task?.cancel() }
  }

  private func fetch() {
    guard let loadRepositories else { return }
    failed = false
    task?.cancel()
    task = Task { [weak self] in
      do {
        let found = try await loadRepositories()
        guard !Task.isCancelled else { return }
        self?.repositories = found
      } catch {
        guard !Task.isCancelled else { return }
        self?.failed = true
      }
      self?.render()
    }
  }

  private var local: [CreateProject] { projects.filter { !CreateProjectPicker.isGithub($0.id) } }
  private var github: [CreateProject] {
    repositories ?? projects.filter { CreateProjectPicker.isGithub($0.id) }
  }

  private func applySearch() {
    list.setSearchPlaceholder(LodyStrings.text(segment == 1 ? "projectPicker.searchGithub" : "projectPicker.searchLocal"))
    list.setSearchText(queries[segment])
  }

  private func render() {
    let searching = !queries[segment].trimmingCharacters(in: .whitespaces).isEmpty
    list.setPlaceholder(LodyStrings.text(searching ? "projectPicker.noMatch" : "projectPicker.empty"))
    let row = { (project: CreateProject) in
      CreateProjectPicker.row(project, machineNames: self.machineNames, selected: self.selectedId)
    }
    if segment == 1 {
      let loaded = loadRepositories == nil || repositories != nil
      let githubQuery = queries[1].trimmingCharacters(in: .whitespaces)
      var rows = CreateProjectPicker.filter(github, queries[1]).map(row)
      if githubQuery.isEmpty {
        rows += CreateProjectPicker.githubStatusRows(loaded: loaded, failed: failed, empty: github.isEmpty)
      }
      let hint = githubQuery.isEmpty && loaded && github.isEmpty ? LodyStrings.text("projectPicker.githubHint") : ""
      show([.group("github", footer: hint, rows)])
    } else {
      show([.group("local", CreateProjectPicker.filter(local, queries[0]).map(row))])
    }
  }

  private func show(_ sections: [LodyListSection]) {
    let ids = sections.flatMap { [$0.id, $0.footer] + $0.rows.map { "\($0.id)|\($0.title)" } }
    guard ids != shown else { return }
    shown = ids
    list.setSections(sections)
  }

  override func event(_ name: String, _ body: [String: Any]) {
    switch name {
    case "segmentChange":
      segment = body["index"] as? Int == 1 ? 1 : 0
      applySearch()
      render()
    case "searchChange":
      queries[segment] = body["text"] as? String ?? ""
      // Reapplying sections inside the field's own change callback ends editing.
      DispatchQueue.main.async { [weak self] in self?.render() }
    case "rowPress":
      guard let id = body["id"] as? String else { return }
      if id == "github-retry" { return fetch() }
      if let project = (local + github).first(where: { $0.id == id }) { onPick?(project) }
    default: break
    }
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
