import AppKit
import LodyData

@MainActor
final class MacDebugController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
  private let runtimeLabel = NSTextField(wrappingLabelWithString: "")
  private let table = NSTableView()
  private let scenes = MacCatalog.scenes

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 520))
    let heading = NSTextField(labelWithString: "Runtime")
    heading.font = .boldSystemFont(ofSize: 13)
    runtimeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    runtimeLabel.textColor = .secondaryLabelColor
    let restart = NSButton(title: "Restart runtime", target: self, action: #selector(restartRuntime))
    let hang = NSButton(title: "Hang runtime (watchdog)", target: self, action: #selector(hangRuntime))
    let actions = NSStackView(views: [restart, hang])
    let catalogHeading = NSTextField(labelWithString: "UI catalog")
    catalogHeading.font = .boldSystemFont(ofSize: 13)
    let column = NSTableColumn(identifier: .init("scene"))
    column.title = "Scene"
    table.addTableColumn(column)
    table.headerView = nil
    table.style = .inset
    table.dataSource = self
    table.delegate = self
    table.target = self
    table.doubleAction = #selector(openScene)
    table.setAccessibilityIdentifier("debug-catalog")
    let scroll = NSScrollView()
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    let stack = NSStackView(views: [heading, runtimeLabel, actions, catalogHeading, scroll])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    stack.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: root.topAnchor),
      stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
      scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
    ])
    view = root
  }

  override func viewWillAppear() {
    super.viewWillAppear()
    let runtime = DataRuntime.current
    runtimeLabel.stringValue = [
      "workspace: \(runtime?.workspace ?? "—")",
      "session: \(runtime?.sessionId ?? "—")",
      "generation: \(runtime?.generation ?? 0)  contract: \(runtime?.contractReady == true ? "ready" : "not ready")",
    ].joined(separator: "\n")
  }

  func numberOfRows(in tableView: NSTableView) -> Int { scenes.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let label = NSTextField(labelWithString: "\(scenes[row].title)  ·  \(scenes[row].id)")
    label.lineBreakMode = .byTruncatingTail
    return label
  }

  @objc private func openScene() {
    guard table.clickedRow >= 0 else { return }
    MacSceneHost.shared.open(scenes[table.clickedRow].id)
  }

  @objc private func restartRuntime() { DataRuntime.current?.debugRestart() }
  @objc private func hangRuntime() { DataRuntime.current?.debugHang() }
}
