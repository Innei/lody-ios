import Foundation
import LodyData

struct MacInspectionLoad<Value> {
  var value: Value?
  var busy = false
  var error: String?
}

@MainActor
final class MacInspectionModel {
  let service: MacInspectionService
  var state = MacInspectionState()
  var changed: (() -> Void)?
  var latestTurn: MacInspectionTurn?
  private(set) var turn: MacInspectionTurn?
  private(set) var selectedTurn: MacInspectionTurn?
  private(set) var files: [MacInspectionFile] = []
  private(set) var base = ""
  private(set) var changesBusy = false
  private(set) var changesError: String?
  private(set) var diffs: [String: MacInspectionLoad<MacInspectionDiff>] = [:]
  private(set) var documents: [MacInspectionTarget: MacInspectionLoad<MacInspectionContent>] = [:]
  private(set) var directories: [String: MacInspectionLoad<MacInspectionDirectory>] = [:]
  var expanded = Set<String>()
  var expandedFolders = Set<String>()
  var changesScroll = 0.0
  var showContext = Set<String>()
  var attachments: [MacInspectionTarget] = []
  var directoryChanged: (() -> Void)?
  private var attachmentReads: [MacInspectionTarget: @MainActor () async throws -> MacInspectionContent] = [:]
  private var savedRanges: [String: (Set<String>, Double)] = [:]
  private var tasks: [String: Task<Void, Never>] = [:]
  private var tokens: [String: UUID] = [:]
  private var generation = 0
  private var rangeKey: String { turn?.id ?? "workspace" }

  init(service: MacInspectionService) { self.service = service }

  func showChanges(entry: MacInspectionTurn?, path: String? = nil) {
    savedRanges[rangeKey] = (expanded, changesScroll)
    cancelLoads()
    turn = entry
    if let entry { selectedTurn = entry }
    state.selection = .changes; state.isOpen = true
    let saved = savedRanges[rangeKey]
    expanded = saved?.0 ?? []; changesScroll = saved?.1 ?? 0
    diffs = [:]; showContext = []; changesError = nil
    if let entry {
      files = entry.files
      if let path { expanded.insert(path) }
      else if saved == nil, let first = files.first { expanded.insert(first.path) }
      for path in expanded { loadDiff(path) }
    } else { loadChanges() }
    changed?()
  }

  func show(_ target: MacInspectionTarget, pinned: Bool = false) {
    state.show(target, pinned: pinned)
    loadDocument(target)
    changed?()
  }

  func showAttachment(_ target: MacInspectionTarget, read: @escaping @MainActor () async throws -> MacInspectionContent) {
    attachmentReads[target] = read
    if !attachments.contains(target) { attachments.append(target) }
    show(target)
  }

  func select(_ selection: MacInspectionState.Selection) {
    state.selection = selection; state.isOpen = true
    if case .document(let target) = selection { loadDocument(target) }
    else { for path in expanded { loadDiff(path) } }
    changed?()
  }

  func toggleDiff(_ path: String) {
    if expanded.contains(path) { expanded.remove(path) }
    else { expanded.insert(path); loadDiff(path) }
    changed?()
  }

  func refresh() {
    switch state.selection {
    case .changes:
      if turn == nil { loadChanges() }
      else { for path in expanded { loadDiff(path, force: true) } }
    case .document(let target): loadDocument(target, force: true)
    }
  }

  func loadDiff(_ path: String, force: Bool = false) {
    if !force, let load = diffs[path], load.busy || load.value.flatMap({ ContentStore.shared.get($0.handle) }) != nil { return }
    diffs[path, default: .init()].busy = true
    let entry = turn?.id
    perform("diff:" + path, operation: { [service] in try await service.diff(path, entry) }) { [weak self] result in
      guard let self else { return }
      diffs[path, default: .init()].busy = false
      switch result {
      case .success(let value): diffs[path]?.value = value; diffs[path]?.error = nil
      case .failure(let error): diffs[path]?.error = error.localizedDescription
      }
    }
  }

  private func loadChanges() {
    changesBusy = true; changed?()
    perform("changes", operation: { [service] in try await service.changes() }) { [weak self] result in
      guard let self else { return }
      changesBusy = false
      switch result {
      case .success(let value):
        files = value.files; base = value.base; changesError = nil
        if expanded.isEmpty, let first = files.first { expanded.insert(first.path) }
        for path in expanded where files.contains(where: { $0.path == path }) { loadDiff(path, force: true) }
      case .failure(let error): changesError = error.localizedDescription
      }
    }
  }

  func loadDocument(_ target: MacInspectionTarget, force: Bool = false) {
    if !force, let load = documents[target], load.busy { return }
    if !force, let value = documents[target]?.value {
      switch value {
      case .url(let url): if FileManager.default.fileExists(atPath: url.path) { return }
      case .stored(let handle): if ContentStore.shared.get(handle) != nil { return }
      }
    }
    documents[target, default: .init()].busy = true
    let read = attachmentReads[target] ?? { [service] in try await service.read(target) }
    perform("document:" + String(describing: target), operation: read) { [weak self] result in
      guard let self, state.tabs.contains(where: { $0.target == target }) else { return }
      documents[target, default: .init()].busy = false
      switch result {
      case .success(let value): documents[target]?.value = value; documents[target]?.error = nil
      case .failure(let error): documents[target]?.error = error.localizedDescription
      }
    }
    changed?()
  }

  func loadDirectory(_ path: String, force: Bool = false) {
    if !force, let load = directories[path], load.busy || load.value != nil { return }
    directories[path, default: .init()].busy = true
    perform("directory:" + path, operation: { [service] in try await service.directory(path) }) { [weak self] result in
      guard let self else { return }
      directories[path, default: .init()].busy = false
      switch result {
      case .success(let value): directories[path]?.value = value; directories[path]?.error = nil
      case .failure(let error): directories[path]?.error = error.localizedDescription
      }
      directoryChanged?()
    }
    changed?()
    directoryChanged?()
  }

  func suspend() {
    cancelLoads()
    // Shared ContentStore may evict these bodies as the active session changes.
    diffs = [:]; documents = [:]; directories = [:]
  }
  private func cancelLoads() {
    generation += 1
    tasks.values.forEach { $0.cancel() }; tasks = [:]; tokens = [:]
    changesBusy = false
    for key in documents.keys { documents[key]?.busy = false }
    for key in directories.keys { directories[key]?.busy = false }
    for key in diffs.keys { diffs[key]?.busy = false }
  }

  private func perform<Value>(_ key: String, operation: @escaping @MainActor () async throws -> Value, apply: @escaping @MainActor (Result<Value, Error>) -> Void) {
    tasks[key]?.cancel()
    let token = UUID(), epoch = generation
    tokens[key] = token
    tasks[key] = Task { [weak self] in
      let result: Result<Value, Error>
      do { result = .success(try await operation()) } catch { result = .failure(error) }
      guard let self, generation == epoch, tokens[key] == token, !Task.isCancelled else { return }
      tasks[key] = nil; tokens[key] = nil
      apply(result); changed?()
    }
  }

  func waitForLoads() async {
    while !tasks.isEmpty { for task in Array(tasks.values) { await task.value } }
  }
}
