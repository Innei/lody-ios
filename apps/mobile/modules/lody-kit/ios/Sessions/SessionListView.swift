import UIKit

// Both layouts render the same catalog projection and keep one owner for actions.
@MainActor
final class SessionListView: UIView {
  private let grouped = LodyGroupedList(appContext: nil)
  private let sidebar = LodySidebar(appContext: nil)
  var forwarded: ((String, [String: Any]) -> Void)?
  var selectedSessionId = "" { didSet { sidebar.setSelectedRowId(selectedSessionId) } }
  private var sections: [LodyListSection] = []
  private var regular: Bool { traitCollection.horizontalSizeClass == .regular }
  override init(frame: CGRect) {
    super.init(frame: frame)
    grouped.forwarded = { [weak self] name, body in self?.forwarded?(name, body) }
    sidebar.onRowPress.onEventSent = { [weak self] body in self?.forwarded?("rowPress", body) }
    sidebar.onRowAction.onEventSent = { [weak self] body in self?.forwarded?("rowAction", body) }
    registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (self: Self, _: UITraitCollection) in self.applyLayout() }
    applyLayout()
  }
  required init?(coder: NSCoder) { fatalError() }
  convenience init() { self.init(frame: .zero) }
  override func layoutSubviews() { super.layoutSubviews(); subviews.forEach { $0.frame = bounds } }
  private func applyLayout() {
    let active: UIView = regular ? sidebar : grouped
    let retired: UIView = regular ? grouped : sidebar
    retired.removeFromSuperview()
    if active.superview == nil { addSubview(active) }
    active.frame = bounds; active.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    render()
  }
  func setContentStyle(_ value: Bool) { grouped.setContentStyle(value) }
  func setPreviewUserId(_ value: String) { grouped.setPreviewUserId(value); sidebar.previewUserId = value }
  func setPreviewWorkspaceId(_ value: String) { grouped.setPreviewWorkspaceId(value); sidebar.previewWorkspaceId = value }
  func setPlaceholder(_ value: String) { grouped.setPlaceholder(value); sidebar.setPlaceholder(value) }
  func setSections(_ value: [LodyListSection]) { sections = value; render() }
  private func render() {
    if regular { sidebar.setSections(sections) }
    else { grouped.setSections(sections) }
  }
}
