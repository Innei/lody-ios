#if DEBUG
import AppKit
import LodyData

/// The study and live session now use the same production interruption surface.
@MainActor
final class MacInterruptionStudy: NSView {
  enum Content { case approval, questions }
  var onFinish: (() -> Void)?
  private let flow: MacPermissionFlow
  private let panel: MacPermissionCard

  init(content: Content) {
    let questions: SessionPermission.Questions? = content == .questions ? .init(questions: [
      .init(id: "organization", header: "Question 1", question: "How should sessions be organized?", options: [
        .init(label: "Group by project", description: "Keep conversations beside the code they belong to.", preview: nil),
        .init(label: "Show recent sessions", description: "List the latest conversations first.", preview: nil),
      ], multiSelect: false, allowCustomAnswer: true, isSecret: false),
      .init(id: "density", header: "Question 2", question: "How much detail should each row show?", options: [
        .init(label: "Title and activity", description: "Include the latest agent activity under the title.", preview: nil),
        .init(label: "Compact titles", description: "Keep more conversations visible in the sidebar.", preview: nil),
      ], multiSelect: false, allowCustomAnswer: true, isSecret: false),
    ], allowCustomAnswer: true) : nil
    let target = SessionPermission(entryId: "study", itemId: "request", requestId: "study", kind: questions == nil ? "edit" : "ask_user_question",
                                   title: "Allow this file edit?", path: questions == nil ? "macOS/ViewControllers/Sidebar/SidebarViewController.swift" : nil,
                                   options: [.init(optionId: "allow", name: "Allow once", kind: "allow_once"), .init(optionId: "deny", name: "Don’t allow", kind: "reject_once")], questionMeta: questions)
    flow = MacPermissionFlow(detail: { _ in nil }, respond: { _, _ in .accepted }, respondQuestions: { _, _, _ in .accepted })
    flow.show(target)
    panel = MacPermissionCard(card: flow.card!)
    super.init(frame: .zero)
    panel.translatesAutoresizingMaskIntoConstraints = false
    addSubview(panel)
    NSLayoutConstraint.activate([panel.leadingAnchor.constraint(equalTo: leadingAnchor), panel.trailingAnchor.constraint(equalTo: trailingAnchor), panel.topAnchor.constraint(equalTo: topAnchor), panel.bottomAnchor.constraint(equalTo: bottomAnchor)])
    panel.onQuestion = { [weak self] in self?.flow.question($0) }
    panel.onAnswer = { [weak self] in self?.flow.answer($0) }
    flow.changed = { [weak self] in
      guard let self else { return }
      if let card = flow.card { panel.update(card); invalidateIntrinsicContentSize() }
      else { onFinish?() }
    }
  }
  required init?(coder: NSCoder) { nil }
  override var intrinsicContentSize: NSSize { panel.intrinsicContentSize }
}
#endif
