import LodyCore
import UIKit

@MainActor
class WorkspaceChangesController: UIViewController {
  let sessionId: String
  let feedback: PreviewFeedback?
  let service: FileDiffService
  private let list = LodyGroupedList(appContext: nil)
  private var result: RuntimeContract.WorkspaceChangesOk?
  private var error = ""
  private var loading = true
  private var load: Task<Void, Never>?

  init(sessionId: String, feedback: PreviewFeedback? = nil, service: FileDiffService = .live) {
    self.sessionId = sessionId
    self.feedback = feedback
    self.service = service
    super.init(nibName: nil, bundle: nil)
    title = LodyStrings.text("workspaceChanges.title")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  isolated deinit { load?.cancel() }

  override func viewDidLoad() {
    super.viewDidLoad()
    list.frame = view.bounds
    list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    list.forwarded = { [weak self] name, body in self?.event(name, body) }
    view.addSubview(list)
    refresh()
  }

  override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    renderHeader()
  }

  private func refresh() {
    load?.cancel()
    loading = true
    error = ""
    result = nil
    render()
    load = Task { [weak self, sessionId, service] in
      let next: Result<RuntimeContract.WorkspaceChanges, Error>
      do { next = .success(try await service.changes(sessionId)) } catch { next = .failure(error) }
      guard !Task.isCancelled, let self else { return }
      switch next {
      case .success(.ok(let value)):
        self.result = value
      case .success(.unavailable(let value)):
        self.error = LodyStrings.text(value.reason == "base_unavailable" ? "diff.reason.baseUnavailable" : "workspaceChanges.error")
      case .failure:
        self.error = LodyStrings.text("workspaceChanges.error")
      }
      self.loading = false
      self.render()
    }
  }

  private func render() {
    var sections: [LodyListSection] = []
    if let result {
      sections.append(Self.section(result))
    }
    if !error.isEmpty {
      let retry = LodyListRow()
      retry.id = "retry"
      retry.title = LodyStrings.text("common.retry")
      retry.action = true
      let section = LodyListSection()
      section.id = "error"
      section.footer = error
      section.rows = [retry]
      sections.append(section)
    }
    var placeholder = LodyStrings.text("workspaceChanges.empty")
    if loading {
      placeholder = LodyStrings.text("common.reading")
    } else if !error.isEmpty {
      placeholder = ""
    }
    list.setPlaceholder(placeholder)
    list.setRefreshing(loading)
    list.setSections(sections)
    renderHeader()
  }

  static func section(_ result: RuntimeContract.WorkspaceChangesOk) -> LodyListSection {
    let files = result.files
    let base = result.base == "diff-store" ? LodyStrings.text("workspaceChanges.localBase") : result.base
    let section = LodyListSection()
    section.id = "changes"
    section.header = LodyStrings.plural("changes.fileCount", files.count)
    if !files.isEmpty, files.allSatisfy({ $0.add != nil && $0.del != nil }) {
      section.headerValue = "+\(files.reduce(0) { $0 + ($1.add ?? 0) }) −\(files.reduce(0) { $0 + ($1.del ?? 0) })"
    }
    section.footer = LodyStrings.text("workspaceChanges.base", ["base": base])
    section.rows = files.map { file in
      let row = LodyListRow()
      row.id = "file:\(file.path)"
      row.title = FilePathText.basename(file.path)
      row.subtitle = FilePathText.dirname(file.path)
      row.subtitleMono = true
      row.filePath = file.path
      row.badge = file.kind.map { LodyStrings.text("workspaceChanges.\($0.rawValue)") } ?? ""
      if let add = file.add, let del = file.del {
        let added = LodyListValueSegment()
        added.text = "+\(add)"
        added.tint = "green"
        let deleted = LodyListValueSegment()
        deleted.text = " −\(del)"
        deleted.tint = "danger"
        row.valueSegments = [added, deleted]
        row.accessibilityValue = added.text + deleted.text
      }
      row.action = true
      row.navigates = true
      row.disclosure = true
      return row
    }
    return section
  }

  private func renderHeader() {
    guard let host = parent?.navigationItem else { return }
    let item = UIBarButtonItem(primaryAction: UIAction(image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in self?.refresh() })
    item.accessibilityLabel = LodyStrings.text("workspaceChanges.refresh")
    item.isEnabled = !loading
    host.rightBarButtonItems = [item]
  }

  private func event(_ name: String, _ body: [String: Any]) {
    switch name {
    case "refresh":
      refresh()
    case "rowPress":
      guard let id = body["id"] as? String else { return }
      if id == "retry" {
        refresh()
        return
      }
      guard let file = result?.files.first(where: { "file:\($0.path)" == id }) else { return }
      openDiff(file.path)
    default:
      break
    }
  }

  func openDiff(_ path: String) {
    let diff = FileDiffController(request: FileDiffRequest(sessionId: sessionId, path: path), feedback: feedback, service: service)
    LodyShell.shared.pushNative(diff, title: FilePathText.basename(path), from: self)
  }
}
