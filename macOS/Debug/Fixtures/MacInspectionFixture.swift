#if DEBUG
import AppKit
import LodyCore
import LodyData

@MainActor
final class MacInspectionFixture {
  private var failures = 0
  private struct Document: Decodable {
    var path: String
    var add: Int
    var del: Int
    var old: String
    var new: String
  }
  private static let documents: [Document] = {
    guard let url = Bundle.main.url(forResource: "InspectionFiles", withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode([Document].self, from: data)) ?? []
  }()
  static var files: [MacInspectionFile] { documents.map { .init(path: $0.path, add: $0.add, del: $0.del) } }
  static var source: String { documents.first?.new ?? "import AppKit\n" }

  var service: MacInspectionService {
    .init(diff: { path, _ in
      try await Task.sleep(for: .milliseconds(80))
      if path.contains("unavailable") { throw Self.offline }
      let document = Self.documents.first { $0.path == path }
      let old = document?.old ?? Self.source
      let new = document?.new ?? Self.source
      let result = RuntimeContract.DiffResultOk(base: .turn, path: path,
        old: .init(kind: path.contains("binary") ? .binary : .text, text: old),
        new: .init(kind: path.contains("deleted") ? .missing : .text, text: path.contains("deleted") ? nil : new))
      let handle = ContentStore.shared.put(.init(data: try JSONEncoder().encode(result), kind: "diff", path: path, session: "s-mac", mimeType: nil))
      return .init(handle: handle, oldKind: result.old.kind.rawValue, newKind: result.new.kind.rawValue)
    }, changes: {
      .init(base: "feature/native-panel", files: Self.files + [.init(path: "docs/current-only.md", add: 2, del: 0), .init(path: "docs/deleted.md", add: 0, del: 4, kind: "deleted"), .init(path: "docs/unavailable.md"), .init(path: "assets/binary.dat")])
    }, read: { [self] target in
      try await Task.sleep(for: .milliseconds(80))
      if target.path.contains("retry") {
        failures += 1
        if failures == 1 { throw Self.offline }
      }
      if target.path.contains("deleted") { throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file no longer exists."]) }
      let data: Data, kind: String
      if target.path.hasSuffix(".png") {
        guard let url = Bundle.main.url(forResource: "InspectionReference", withExtension: "png") else { throw Self.offline }
        data = try Data(contentsOf: url); kind = "image"
      } else { data = Data((Self.documents.first { $0.path == target.path }?.new ?? Self.source).utf8); kind = "text" }
      let handle = ContentStore.shared.put(.init(data: data, kind: kind, path: target.path, session: "s-mac", mimeType: kind == "image" ? "image/png" : nil))
      return .stored(handle)
    }, directory: { path in
      var entries: [String: Bool] = [:]
      let paths = Self.files.map(\.path) + ["changes-reference.png", "retry.swift", "docs/notes.md"]
      let prefix = path.isEmpty ? "" : path + "/"
      for item in paths where item.hasPrefix(prefix) {
        let remaining = String(item.dropFirst(prefix.count)).split(separator: "/")
        if let name = remaining.first { entries[String(name)] = remaining.count > 1 }
      }
      return .init(entries: entries.map { .init(name: $0.key, directory: $0.value) }, truncated: false)
    })
  }
  private static var offline: Error { NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Machine is offline. Reconnect and try again."]) }

  static func windows(width: CGFloat = 1100) -> [NSWindow] {
    let fixture = MacInspectionFixture()
    var environment = MacFixtures.environment(history: 0, approval: false)
    environment.pane = { id in
      let entries: [[String: Any]] = [
        ["id": "user", "role": "user", "finished": true, "status": "completed", "items": [["itemId": "u", "type": "text", "text": "Keep the native controls and align the composer with iOS."]]],
        ["id": "fixture-turn", "role": "assistant", "finished": true, "status": "completed", "timestamp": "2026-11-02 10:32", "items": [["itemId": "a", "type": "text", "text": "I’ve reused the composer’s context tray for queued messages. Permission choices now submit with one click, and the primary action stays circular."]], "fileDiffs": Self.files.map { ["path": $0.path, "add": $0.add ?? 0, "del": $0.del ?? 0] as [String: Any] }],
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
    controller.window?.setContentSize(.init(width: width, height: width >= 1382 ? 900 : 820))
    if let workspace = controller.workspace { MacTabCoordinator.shared.select(workspace) }
    controller.workspace?.toggleInspection(nil)
    return controller.window.map { [$0] } ?? []
  }
}
#endif
