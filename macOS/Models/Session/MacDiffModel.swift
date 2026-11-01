import Foundation
import LodyCore
import LodyData

struct MacChangedFile: Equatable, Sendable {
  var path: String
  var add = 0
  var del = 0
  var title: String { "\(path)  +\(add) −\(del)" }
}

@MainActor
final class MacDiffModel {
  enum Scope { case turn, session }
  let entryId: String?
  private let sessionId: String
  private let service: MacDiffService
  private let turnFiles: [MacChangedFile]
  private var revision = 0
  private(set) var scope: Scope
  private(set) var files: [MacChangedFile] = []
  private(set) var selectedPath: String?
  private(set) var patch = ""
  private(set) var message = ""
  private(set) var loading = false
  private(set) var base = ""
  var changed: (() -> Void)?

  init(sessionId: String, entryId: String? = nil, files: [MacChangedFile] = [], service: MacDiffService) {
    self.sessionId = sessionId
    self.entryId = entryId
    turnFiles = files
    self.service = service
    scope = entryId == nil ? .session : .turn
  }

  func setScope(_ value: Scope) async {
    guard value != .turn || entryId != nil else { return }
    scope = value
    selectedPath = nil
    await load()
  }

  func load() async {
    revision += 1
    let request = revision
    loading = true
    message = ""
    patch = ""
    changed?()
    defer { if request == revision { loading = false; changed?() } }
    do {
      if scope == .turn { files = turnFiles; base = Self.text("mac.diff.thisTurn") }
      else {
        let result = try await service.changes(sessionId)
        guard request == revision, !Task.isCancelled else { return }
        switch result {
        case .ok(let value):
          files = value.files.map { MacChangedFile(path: $0.path, add: $0.add ?? 0, del: $0.del ?? 0) }
          base = value.base
        case .unavailable:
          files = []
          message = Self.text("mac.diff.unavailable")
          return
        }
      }
      guard request == revision, !Task.isCancelled else { return }
      let path = files.first(where: { $0.path == selectedPath })?.path ?? files.first?.path
      guard let path else { message = Self.text("mac.diff.empty"); return }
      await read(path, revision: request)
    } catch { if request == revision { message = Self.text("mac.diff.failed") } }
  }

  func select(_ path: String) async {
    guard files.contains(where: { $0.path == path }) else { return }
    revision += 1
    let request = revision
    loading = true
    message = ""
    patch = ""
    selectedPath = path
    changed?()
    await read(path, revision: request)
    if request == revision { loading = false; changed?() }
  }

  private func read(_ path: String, revision request: Int) async {
    selectedPath = path
    do {
      let result = try await service.diff(.init(sessionId: sessionId, entryId: scope == .turn ? entryId : nil, path: path))
      guard request == revision, !Task.isCancelled else { return }
      switch result {
      case .unavailable: message = Self.text("mac.diff.unavailable")
      case .ok(let value):
        guard value.path == path else { message = Self.text("mac.diff.unavailable"); return }
        if value.old.kind == .binary || value.new.kind == .binary { message = Self.text("mac.diff.binary"); return }
        if value.old.kind == .tooLarge || value.new.kind == .tooLarge { message = Self.text("mac.diff.large"); return }
        let old = value.old.kind == .missing ? "" : value.old.text
        let new = value.new.kind == .missing ? "" : value.new.text
        guard let old, let new else { message = Self.text("mac.diff.unavailable"); return }
        guard old.utf8.count + new.utf8.count <= 2 * 1024 * 1024,
              old.filter({ $0 == "\n" }).count + new.filter({ $0 == "\n" }).count <= 20_000 else {
          message = Self.text("mac.diff.large"); return
        }
        if old.utf8.elementsEqual(new.utf8) { message = Self.text("mac.diff.unchanged"); return }
        let output = await Task.detached(priority: .userInitiated) { UnifiedPatch.make(path: path, old: old, new: new) }.value
        guard request == revision, !Task.isCancelled else { return }
        patch = output
      }
    } catch { if request == revision { message = Self.text("mac.diff.failed") } }
  }

  private static func text(_ key: String) -> String { String(localized: String.LocalizationValue(key), bundle: .lodyMac) }
}
