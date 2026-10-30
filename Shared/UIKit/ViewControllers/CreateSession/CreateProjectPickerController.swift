import LodyCore
import UIKit

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
    title = String(localized: "create.row.selectProject", bundle: .lody)
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
      item.accessibilityLabel = String(localized: "projectPicker.browse.accessibility", bundle: .lody)
      navigationItem.rightBarButtonItem = item
    }
    list.setSegments([String(localized: "projectPicker.local", bundle: .lody), String(localized: "projectPicker.github", bundle: .lody)])
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
    list.setSearchPlaceholder(String(localized: String.LocalizationValue(segment == 1 ? "projectPicker.searchGithub" : "projectPicker.searchLocal"), bundle: .lody))
    list.setSearchText(queries[segment])
  }

  private func render() {
    let searching = !queries[segment].trimmingCharacters(in: .whitespaces).isEmpty
    list.setPlaceholder(String(localized: String.LocalizationValue(searching ? "projectPicker.noMatch" : "projectPicker.empty"), bundle: .lody))
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
      let hint = githubQuery.isEmpty && loaded && github.isEmpty ? String(localized: "projectPicker.githubHint", bundle: .lody) : ""
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
