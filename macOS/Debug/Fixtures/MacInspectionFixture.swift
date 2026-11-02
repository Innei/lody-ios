#if DEBUG
import AppKit
import LodyCore
import LodyData

@MainActor
final class MacInspectionFixture {
  private var failures = 0
  static let files: [MacInspectionFile] = [
    .init(path: "macOS/Views/MacComposerView.swift", add: 22, del: 10),
    .init(path: "macOS/ViewControllers/MacSessionController.swift", add: 3, del: 3),
    .init(path: "macOS/Views/MacQueueView.swift", add: 13, del: 6),
    .init(path: "README.md", add: 4, del: 0),
    .init(path: "docs/deleted.md", add: 0, del: 4, kind: "deleted"),
    .init(path: "docs/unavailable.md"),
    .init(path: "assets/binary.dat"),
    .init(path: "docs/large.txt"),
    .init(path: "verification/last-file.swift", add: 1, del: 1),
  ]
  static let source = "import AppKit\n\n@MainActor\nfinal class MacComposerView: NSView {\n  private let input = NSTextView()\n  private var queuedMessages: [String] = []\n\n  func render() {\n    input.isEditable = true\n    needsLayout = true\n  }\n}\n"

  var service: MacInspectionService {
    .init(diff: { [self] path, _ in
      try await Task.sleep(for: .milliseconds(80))
      if path.contains("unavailable") { throw Self.offline }
      let old = Self.source.replacingOccurrences(of: "needsLayout = true", with: "layoutSubtreeIfNeeded()")
      let result = RuntimeContract.DiffResultOk(base: .turn, path: path,
        old: .init(kind: path.contains("binary") ? .binary : .text, text: old),
        new: .init(kind: path.contains("deleted") ? .missing : .text, text: path.contains("deleted") ? nil : Self.source))
      let handle = ContentStore.shared.put(.init(data: try JSONEncoder().encode(result), kind: "diff", path: path, session: "s-mac", mimeType: nil))
      return .init(handle: handle, oldKind: result.old.kind.rawValue, newKind: result.new.kind.rawValue)
    }, changes: {
      .init(base: "feature/native-panel", files: Self.files + [.init(path: "docs/current-only.md", add: 2, del: 0)])
    }, read: { [self] target in
      try await Task.sleep(for: .milliseconds(80))
      if target.path.contains("retry") {
        failures += 1
        if failures == 1 { throw Self.offline }
      }
      if target.path.contains("deleted") { throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file no longer exists."]) }
      let data: Data, kind: String
      if target.path.hasSuffix(".png") {
        let image = NSBitmapImageRep(cgImage: MacFixtureMedia.swatch(seed: "inspection", size: CGSize(width: 1200, height: 800)))
        data = image.representation(using: .png, properties: [:]) ?? Data(); kind = "image"
      } else { data = Data((Self.source + String(repeating: "// Preserve the file reading position.\n", count: 160)).utf8); kind = "text" }
      let handle = ContentStore.shared.put(.init(data: data, kind: kind, path: target.path, session: "s-mac", mimeType: kind == "image" ? "image/png" : nil))
      return .stored(handle)
    }, directory: { path in
      switch path {
      case "": return .init(entries: [.init(name: "macOS", directory: true), .init(name: "docs", directory: true), .init(name: "README.md", directory: false), .init(name: "preview.png", directory: false), .init(name: "retry.swift", directory: false)], truncated: false)
      case "macOS": return .init(entries: [.init(name: "Views", directory: true), .init(name: "ViewControllers", directory: true)], truncated: false)
      case "macOS/Views": return .init(entries: [.init(name: "MacComposerView.swift", directory: false), .init(name: "MacQueueView.swift", directory: false)], truncated: false)
      default: return .init(entries: [.init(name: "notes.md", directory: false)], truncated: true)
      }
    })
  }
  private static var offline: Error { NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Machine is offline. Reconnect and try again."]) }

  static func windows(width: CGFloat = 1100) -> [NSWindow] {
    let fixture = MacInspectionFixture()
    var environment = MacFixtures.environment(history: 0, approval: false)
    environment.pane = { id in
      let entries: [[String: Any]] = [
        ["id": "user", "role": "user", "finished": true, "status": "completed", "items": [["itemId": "u", "type": "text", "text": "Keep the native controls and align the composer with iOS."]]],
        ["id": "fixture-turn", "role": "assistant", "finished": true, "status": "completed", "timestamp": "2026-11-02 10:32", "items": [["itemId": "a", "type": "text", "text": "I have reused the composer’s context tray for queued messages. Review the changes on the right."]], "fileDiffs": Self.files.map { ["path": $0.path, "add": $0.add ?? 0, "del": $0.del ?? 0] as [String: Any] }],
      ]
      let json = String(decoding: (try? JSONSerialization.data(withJSONObject: entries)) ?? Data(), as: UTF8.self)
      let source = MacTranscriptSource(start: { changed in changed(SessionFeedState(status: "live", entriesJSON: json)) }, stop: {}, detail: { _ in nil }, respond: { _, _ in .accepted }, media: MacFixtureMedia())
      var input = MacComposerModel(mode: .reply); input.replyReady = true; input.replyCapability = MacComposerFixture.capability
      let composer = MacComposerController(model: input, service: .init(options: { _, _ in throw OutboxError.scopeExpired }, create: { _, _ in }, reply: { _, _ in }))
      let pane = MacSessionController(sessionId: id, source: source, composer: composer)
      pane.inspectionModel = MacInspectionModel(service: fixture.service)
      return pane
    }
    let controller = MainWindowController(environment: environment, sessionId: "s-mac")
    controller.window?.setContentSize(.init(width: width, height: 820))
    if let workspace = controller.workspace { MacTabCoordinator.shared.select(workspace) }
    controller.workspace?.toggleInspection(nil)
    return controller.window.map { [$0] } ?? []
  }
}
#endif
