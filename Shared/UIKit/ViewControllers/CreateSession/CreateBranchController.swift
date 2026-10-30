import LodyCore
import UIKit

@MainActor
final class CreateBranchController: CreateListController {
  var onPick: ((String) -> Void)?
  var onMore: (() -> Void)?
  private let repo: String
  private var page = CreateSessionPage(chat: false)
  private var cachedOnly = false
  private var query = ""

  init(repo: String) {
    self.repo = repo
    super.init(nibName: nil, bundle: nil)
    title = String(localized: "create.branch.title", bundle: .lody)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    list.setSearchPlaceholder(String(localized: "create.branch.search", bundle: .lody))
    render()
  }

  func update(_ page: CreateSessionPage, cachedOnly: Bool) {
    self.page = page
    self.cachedOnly = cachedOnly
    if isViewLoaded { render() }
  }

  private func render() {
    let branches = page.branches
    let names = branches?.matching(query) ?? []
    var rows = names.map { name in
      let value = name == branches?.defaultBranch ? String(localized: "create.branch.default", bundle: .lody) : ""
      let selected = name == page.branch ? String(localized: "settings.history.selected", bundle: .lody) : ""
      return LodyListRow.item("branch:" + name, name, value: value, selected: name == page.branch,
        accessibilityValue: [value, selected].filter { !$0.isEmpty }.joined(separator: ", "))
    }
    let incomplete = branches == nil || branches?.nextPage != nil
    if page.branchesLoading {
      rows.append(.item("branches-loading", String(localized: "common.reading", bundle: .lody), action: false))
    } else if incomplete && cachedOnly {
      rows.append(.item("branches-cached", String(localized: "create.branch.cachedHint", bundle: .lody), action: false))
    } else if page.branchesFailed {
      rows.append(.item("branches-more", String(localized: "create.branch.failed", bundle: .lody), image: "arrow.clockwise"))
    } else if incomplete {
      rows.append(.item("branches-more", String(localized: "create.branch.more", bundle: .lody), image: "arrow.down"))
    } else if names.isEmpty {
      rows.append(.item("branches-empty", String(localized: String.LocalizationValue(query.isEmpty ? "create.branch.empty" : "create.branch.noMatch"), bundle: .lody), action: false))
    }
    list.setSections([.group("branches", header: repo, rows)])
    // Search all pages, but never spin on a failed request or an offline snapshot.
    if view.window != nil && !query.isEmpty && incomplete && !cachedOnly && !page.branchesLoading && !page.branchesFailed {
      onMore?()
    }
  }

  override func event(_ name: String, _ body: [String: Any]) {
    if name == "searchChange" {
      query = (body["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      DispatchQueue.main.async { [weak self] in self?.render() }
    } else if name == "rowPress", let id = body["id"] as? String {
      if id == "branches-more" { onMore?(); return }
      guard id.hasPrefix("branch:"), let names = page.branches?.names else { return }
      let branch = String(id.dropFirst(7))
      guard names.contains(branch) else { return }
      onPick?(branch)
      navigationController?.popViewController(animated: true)
    }
  }
}
