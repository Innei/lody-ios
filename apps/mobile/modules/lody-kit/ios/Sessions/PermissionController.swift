import LodyCore
import UIKit

@MainActor
final class PermissionController: UIViewController {
  private let sessionId: String
  private let service: PermissionService
  private let list = LodyGroupedList(appContext: nil)
  private var target: SessionPermission?
  private var questions: PermissionQuestionView?
  private var options: [SessionPermission.Option] = []
  private var command = ""
  private var error = ""
  private var busy = false
  private var detailFailed = false
  private var revision = 0
  private var detailTask: Task<Void, Never>?
  private var sendTask: Task<Void, Never>?
  private enum Phase { case open, closing, closed }
  private var phase = Phase.open
  private var outcome: (answer: String?, cancelled: Bool) = (nil, true)
  var onClose: ((String?, Bool) -> Void)?

  init(sessionId: String, service: PermissionService = .live) {
    self.sessionId = sessionId
    self.service = service
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  isolated deinit { detailTask?.cancel(); sendTask?.cancel() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemGroupedBackground
    list.frame = view.bounds
    list.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(list)
    list.forwarded = { [weak self] event, body in
      guard event == "rowPress", let id = body["id"] as? String else { return }
      guard let self else { return }
      if id == "permission-retry", let target { loadDetail(target) }
      else { answer(id) }
    }
    render()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if phase == .closing { dismissSheet() }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    if phase == .open, SettingsPage.leaving(self) {
      phase = .closing
      detailTask?.cancel()
      sendTask?.cancel()
    }
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    guard phase != .closed, SettingsPage.leaving(self) else { return }
    phase = .closed
    detailTask?.cancel()
    sendTask?.cancel()
    onClose?(outcome.answer, outcome.cancelled)
  }

  func update(_ next: SessionPermission?, ready: Bool) {
    guard phase == .open, ready else { return }
    guard let next else { close(); return }
    guard next != target else { return }
    resetTarget()
    target = next
    options = next.options ?? []
    loadViewIfNeeded()
    if let meta = next.questionMeta {
      let questionView = PermissionQuestionView(meta: meta)
      questions = questionView
      questionView.frame = view.bounds
      questionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      questionView.prompt = { [weak self] alert in self?.present(alert, animated: true) }
      questionView.onSubmit = { [weak self] answers in
        guard let self else { return }
        guard let option = options.first(where: { $0.kind?.hasPrefix("allow") == true }) else {
          error = LodyStrings.text("permission.error.options")
          render()
          return
        }
        answer(option.optionId, answers: answers)
      }
      view.addSubview(questionView)
    } else if next.kind == "ask_user_question" {
      options = []
      error = LodyStrings.text("permission.error.options")
    } else {
      loadDetail(next)
    }
    render()
  }

  func showInvalidRequest(_ message: String) {
    guard phase == .open else { return }
    resetTarget()
    error = message
    loadViewIfNeeded()
    render()
  }

  private func resetTarget() {
    revision += 1
    detailTask?.cancel()
    sendTask?.cancel()
    target = nil
    busy = false
    error = ""
    command = ""
    detailFailed = false
    options = []
    questions?.removeFromSuperview()
    questions = nil
  }

  private func loadDetail(_ target: SessionPermission) {
    detailFailed = false
    error = ""
    render()
    let requestRevision = revision
    detailTask = Task { [weak self, service, sessionId] in
      do {
        let detail = try await service.detail(sessionId, target)
        guard let self, !Task.isCancelled, phase == .open, self.revision == requestRevision else { return }
        if target.options == nil {
          options = (detail.options ?? []).map { .init(optionId: $0.optionId, name: $0.name, kind: $0.kind) }
        }
        for block in detail.blocks {
          guard case .object(let fields) = block, fields["type"] == .string("terminal_command") else { continue }
          let value = try JSONDecoder().decode(PermissionCommand.self, from: JSONEncoder().encode(block))
          command = "$ " + ([value.command] + (value.args ?? [])).joined(separator: " ")
          if let cwd = value.cwd { command += "\n" + cwd }
          break
        }
        render()
      } catch {
        guard let self, !Task.isCancelled, phase == .open, self.revision == requestRevision else { return }
        detailFailed = true
        DiagnosticsStore.shared.record("permission", "detail_failed", fields: ["code": String((error as NSError).code)])
        self.error = LodyStrings.text("permission.error.options")
        render()
      }
    }
  }

  private func answer(_ optionId: String, answers: [String: RuntimeContract.JSONValue]? = nil) {
    guard !busy, phase == .open, let target else { return }
    precondition(options.contains { $0.optionId == optionId }, "Unknown permission option")
    busy = true
    error = ""
    render()
    let requestRevision = revision
    let params = RuntimeContract.RespondPermissionParams(
      sessionId: sessionId, entryId: target.entryId, itemId: target.itemId,
      requestId: target.requestId, optionId: optionId, answers: answers
    )
    sendTask = Task { [weak self, service] in
      do {
        let result = try await service.respond(params)
        guard let self, !Task.isCancelled, phase == .open, self.revision == requestRevision else { return }
        busy = false
        switch result {
        case .accepted: close(answer: target.requestId)
        case .stale: error = LodyStrings.text("permission.error.stale")
        case .conflict: error = LodyStrings.text("permission.error.answered")
        }
        render()
      } catch {
        guard let self, !Task.isCancelled, phase == .open, self.revision == requestRevision else { return }
        busy = false
        DiagnosticsStore.shared.record("permission", "respond_failed", fields: ["code": String((error as NSError).code)])
        self.error = LodyStrings.text("permission.error.send")
        render()
      }
    }
  }

  private func close(answer: String? = nil) {
    guard phase == .open else { return }
    phase = .closing
    detailTask?.cancel()
    sendTask?.cancel()
    outcome = (answer, false)
    dismissSheet()
  }

  private func dismissSheet() {
    // Remote resolution can arrive while the shell is still presenting this page.
    guard let sheet = navigationController, !sheet.isBeingPresented else { return }
    sheet.presentingViewController?.dismiss(animated: true)
  }

  private func render() {
    guard isViewLoaded else { return }
    list.isHidden = questions != nil
    questions?.update(busy: busy, error: error)
    let title = LodyStrings.text(questions == nil ? "permission.title" : "question.title")
    parent?.navigationItem.title = title
    guard questions == nil else { return }
    var section = LodyListSection()
    section.id = "permission"
    section.header = target?.title ?? LodyStrings.text(error.isEmpty ? "permission.waiting" : "permission.title")
    section.headerProminent = true
    section.footer = error
    if !command.isEmpty || target?.path != nil {
      var row = LodyListRow()
      row.id = "permission-command"
      row.subtitle = command.isEmpty ? target?.path ?? "" : command
      row.subtitleMono = true
      row.wrapSubtitle = true
      section.rows.append(row)
    }
    section.rows += options.map { option in
      var row = LodyListRow()
      row.id = option.optionId
      row.title = option.name
      row.action = !busy
      row.destructive = option.kind?.hasPrefix("reject") == true
      return row
    }
    if detailFailed {
      var retry = LodyListRow()
      retry.id = "permission-retry"
      retry.title = LodyStrings.text("common.retry")
      retry.action = !busy
      section.rows.append(retry)
    }
    list.setSections([section], animated: false)
  }
}

private struct PermissionCommand: Decodable {
  let command: String
  let args: [String]?
  let cwd: String?
}
