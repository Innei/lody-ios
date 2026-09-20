import Foundation
import CryptoKit
import Darwin

/// A small display snapshot and submission receipts, never a second catalog DB.
enum ShareStore {
  /// Short synchronous critical sections only; shared by the app and extension.
  /// The lock lives outside the receipt directory, so logout never replaces it.
  static func locked<T>(_ action: () throws -> T) throws -> T {
    guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.innei.lody") else {
      throw CocoaError(.fileNoSuchFile)
    }
    let fd = open(container.appendingPathComponent("LodyShare.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
    defer { flock(fd, LOCK_UN) }
    return try action()
  }
  static func authenticated<T>(_ token: String, _ action: () throws -> T) throws -> T {
    try locked {
      guard try AuthKeychain.read() == token else { throw CocoaError(.userCancelled) }
      return try action()
    }
  }
  static var root: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.innei.lody")?
      .appendingPathComponent("Library/LodyShare", isDirectory: true)
  }
  static func read(_ url: URL) throws -> [String: Any] {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= 2 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
    return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
  }
  static func write(_ value: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    guard data.count <= 2 * 1024 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    var directory = url.deletingLastPathComponent()
    var values = URLResourceValues(); values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
  }
  static func snapshot() -> [String: Any] {
    guard let root else { return [:] }
    return (try? read(root.appendingPathComponent("snapshot.json"))) ?? [:]
  }
  static func currentSnapshot() throws -> [String: Any] {
    try locked {
      guard try AuthKeychain.read() != nil else { return [:] }
      return snapshot()
    }
  }
  static func publish(_ value: [String: Any]) throws {
    guard let root else { throw CocoaError(.fileNoSuchFile) }
    try write(value, to: root.appendingPathComponent("snapshot.json"))
  }
  static func savePreferences(_ prefs: [String: Any], user: String, workspace: String) throws {
    try locked {
      guard try AuthKeychain.read() != nil else { return }
      var cached = snapshot()
      guard cached["userId"] as? String == user, cached["workspaceId"] as? String == workspace else { return }
      cached["prefs"] = prefs; cached["context"] = prefs["context"]
      try publish(cached)
    }
  }
  static func clear() throws {
    guard let root else { return }
    try publish([:])
    let receipts = root.appendingPathComponent("receipts", isDirectory: true)
    if FileManager.default.fileExists(atPath: receipts.path) { try FileManager.default.removeItem(at: receipts) }
  }
  static func sessionID(user: String, workspace: String, request: String) -> String {
    // Same UTF-8 JSON tuple and SHA-256 as Cloud; escaped slashes are forbidden.
    let data = try! JSONSerialization.data(withJSONObject: [user, workspace, request], options: [.withoutEscapingSlashes])
    return "share-" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  static func receiptURL(_ request: String) throws -> URL {
    guard UUID(uuidString: request) != nil, let root else { throw CocoaError(.fileNoSuchFile) }
    return root.appendingPathComponent("receipts/\(request)/receipt.json")
  }
  static func saveDraft(_ draft: [String: Any], request: String) throws -> [String: Any] {
    let url = try receiptURL(request)
    var committed = false
    defer {
      if !committed { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }
    var saved = draft
    var files: [[String: Any]] = []
    for var file in draft["attachments"] as? [[String: Any]] ?? [] {
      guard let uri = file["uri"] as? String, let source = URL(string: uri), source.isFileURL,
        source.resolvingSymlinksInPath().path.hasPrefix(FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path + "/") else { throw CocoaError(.fileReadInvalidFileName) }
      let attributes = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      guard attributes.isRegularFile == true, let size = attributes.fileSize, size > 0, size <= 100 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
      let directory = url.deletingLastPathComponent().appendingPathComponent("files", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let target = directory.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
      try FileManager.default.copyItem(at: source, to: target)
      try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
      file["uri"] = target.absoluteString; files.append(file)
    }
    saved["attachments"] = files; saved["requestId"] = request; saved["phase"] = "draft"
    try write(saved, to: url)
    committed = true
    return saved
  }
  static func pending(user: String, workspace: String) -> [[String: Any]] {
    guard let directory = root?.appendingPathComponent("receipts"),
      let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
    return urls.compactMap { try? read($0.appendingPathComponent("receipt.json")) }.filter {
      $0["userId"] as? String == user && $0["workspaceId"] as? String == workspace && $0["phase"] as? String != "submitted"
    }
  }
}
