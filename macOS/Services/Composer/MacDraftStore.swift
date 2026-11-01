import CryptoKit
import Foundation
import LodyCore
import LodyData

@MainActor
final class MacDraftStore {
  struct Scope: Codable, Equatable {
    var user: String
    var workspace: String
    var session: String
  }
  struct Selection: Codable, Equatable {
    var projectId: String
    var chat: Bool
    var prefs: CreatePrefs?
  }
  struct File: Codable, Equatable {
    var id: String
    var name: String
    var storedName: String
    var image: Bool
    var bytes: Int
  }
  struct Record: Codable, Equatable {
    var scope: Scope
    var revision: String
    var text: String
    var files: [File]
    var selection: Selection?
    var sendId: String?
  }
  struct Loaded {
    var record: Record
    var attachments: [MacDraftAttachment]
  }

  static let changed = Notification.Name("LodyMacDraftDidChange")
  static let shared = MacDraftStore(root: LodyUIVerify.enabled
    ? FileManager.default.temporaryDirectory.appendingPathComponent("lody-mac-drafts-\(ProcessInfo.processInfo.processIdentifier)")
    : LodyStorage.root.appendingPathComponent("Drafts", isDirectory: true))
  private let root: URL
  private let manager = FileManager.default

  init(root: URL) { self.root = root }

  func load(_ scope: Scope) throws -> Loaded? {
    guard let record = try read(folder(scope).appendingPathComponent("draft.json"), scope) else { return nil }
    return Loaded(record: record, attachments: record.files.map { file in
      let url = folder(scope).appendingPathComponent("files").appendingPathComponent(file.storedName)
      return MacDraftAttachment(id: file.id, name: file.name, url: url, isImage: file.image, bytes: file.bytes,
                                thumbnail: file.image ? MacDraftAttachment.thumbnail(url) : nil)
    })
  }

  @discardableResult
  func save(_ scope: Scope, text: String, attachments: [MacDraftAttachment], selection: Selection?, owner: String) throws -> Loaded {
    let directory = folder(scope).appendingPathComponent("files", isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var files: [File] = []
    for file in attachments {
      let storedName = Self.digest(file.id)
      let destination = directory.appendingPathComponent(storedName)
      if !manager.fileExists(atPath: destination.path) { try manager.copyItem(at: file.url, to: destination) }
      files.append(File(id: file.id, name: file.name, storedName: storedName, image: file.isImage, bytes: file.bytes))
    }
    let record = Record(scope: scope, revision: UUID().uuidString, text: text, files: files, selection: selection, sendId: nil)
    let path = folder(scope).appendingPathComponent("draft.json")
    if text.isEmpty && files.isEmpty && selection == nil {
      if manager.fileExists(atPath: path.path) { try manager.removeItem(at: path) }
    } else { try write(record, path) }
    try cleanFiles(scope)
    notify(scope, owner: owner)
    return Loaded(record: record, attachments: files.enumerated().map { index, file in
      let original = attachments[index]
      return MacDraftAttachment(id: file.id, name: file.name, url: directory.appendingPathComponent(file.storedName),
                                isImage: file.image, bytes: file.bytes, thumbnail: original.thumbnail)
    })
  }

  func handoff(_ scope: Scope, sendId: String) throws {
    guard var record = try load(scope)?.record else { throw OutboxError.invalidRecord }
    record.sendId = sendId
    try write(record, handoffPath(scope, sendId))
    // Keep the current draft until the outbox accepts it. A crash or failed write
    // can therefore recover the input; the handoff separately retains its files.
  }

  func matchesHandoff(_ scope: Scope, sendId: String, text: String, ids: [String]) -> Bool {
    guard let record = try? read(handoffPath(scope, sendId), scope) else { return false }
    guard let current = try? read(folder(scope).appendingPathComponent("draft.json"), scope), current.revision == record.revision else { return false }
    return record.text == text && record.files.map(\.id) == ids
  }

  func complete(_ scope: Scope, sendId: String, keepAssets: Bool = false) throws {
    let handoff = handoffPath(scope, sendId)
    guard var sent = try read(handoff, scope) else { return }
    let current = folder(scope).appendingPathComponent("draft.json")
    if var draft = try read(current, scope) {
      draft.sendId = sendId
      if draft == sent { try manager.removeItem(at: current) }
    }
    if keepAssets {
      // The create outbox is durable, but its first turn still needs the files.
      sent.selection = nil
      try write(sent, handoff)
    } else { try manager.removeItem(at: handoff) }
    try cleanFiles(scope)
    notify(scope, owner: "")
  }

  func settle(_ scope: Scope, delivered: Set<String>) throws {
    for path in (try? manager.contentsOfDirectory(at: folder(scope), includingPropertiesForKeys: nil)) ?? [] where path.lastPathComponent.hasPrefix("send-") {
      if let record = try read(path, scope), let id = record.sendId, delivered.contains(id) { try complete(scope, sendId: id) }
    }
  }

  private func write(_ record: Record, _ url: URL) throws {
    try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try JSONEncoder().encode(record).write(to: url, options: .atomic)
    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  private func read(_ url: URL, _ scope: Scope) throws -> Record? {
    guard manager.fileExists(atPath: url.path) else { return nil }
    let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
    guard record.scope == scope, record.files.allSatisfy({ $0.storedName == Self.digest($0.id) }) else { throw OutboxError.invalidRecord }
    return record
  }

  private func cleanFiles(_ scope: Scope) throws {
    let directory = folder(scope)
    let manifests = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    var retained = Set<String>()
    for manifest in manifests where manifest.pathExtension == "json" {
      // An unreadable manifest may own the only copy; stop rather than delete it.
      if let record = try read(manifest, scope) { retained.formUnion(record.files.map(\.storedName)) }
    }
    let files = directory.appendingPathComponent("files")
    for file in (try? manager.contentsOfDirectory(at: files, includingPropertiesForKeys: nil)) ?? [] where !retained.contains(file.lastPathComponent) {
      try manager.removeItem(at: file)
    }
  }

  private func folder(_ scope: Scope) -> URL {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let value = String(decoding: (try? encoder.encode(scope)) ?? Data(), as: UTF8.self)
    return root.appendingPathComponent(Self.digest(value), isDirectory: true)
  }
  private func handoffPath(_ scope: Scope, _ id: String) -> URL { folder(scope).appendingPathComponent("send-" + Self.digest(id) + ".json") }
  private func notify(_ scope: Scope, owner: String) {
    NotificationCenter.default.post(name: Self.changed, object: self, userInfo: ["scope": folder(scope).lastPathComponent, "owner": owner])
  }
  func ownsNotification(scopeKey: String?, sender: String?, scope: Scope, owner: String) -> Bool {
    scopeKey == folder(scope).lastPathComponent && sender != owner
  }
  private static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
}
