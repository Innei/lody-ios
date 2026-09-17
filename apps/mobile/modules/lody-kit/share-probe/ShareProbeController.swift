import UIKit
import UniformTypeIdentifiers

/// Transport spike only. The production shared composer is deliberately not migrated yet.
@MainActor
final class ShareProbeController: UIViewController, UITextViewDelegate {
  private let runtime = ShareProbeRuntime()
  private let editor = UITextView()
  private let status = UILabel()
  private let workspaceButton = UIButton(type: .system)
  private let agentButton = UIButton(type: .system)
  private let sendButton = UIButton(type: .system)
  private let closeButton = UIButton(type: .system)
  private var workspaces: [ShareProbeRuntime.Workspace] = []
  private var workspaceId = ""
  private var agent: ShareProbeAgent?
  private var attempted = false
  private var connected = false
  private var task: Task<Void, Never>?
  private var loadingItems = 0
  private var sharedText: [Int: String] = [:]

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    view.tintColor = .systemBlue
    let title = UILabel()
    title.text = "Lody Send Probe"
    title.font = .preferredFont(forTextStyle: .headline)
    status.font = .preferredFont(forTextStyle: .footnote)
    status.textColor = .secondaryLabel
    status.numberOfLines = 0
    status.accessibilityIdentifier = "share-probe.status"
    editor.font = .preferredFont(forTextStyle: .body)
    editor.backgroundColor = .secondarySystemBackground
    editor.layer.cornerRadius = 12
    editor.delegate = self
    editor.accessibilityLabel = "Message"
    editor.accessibilityIdentifier = "share-probe.message"
    workspaceButton.setTitle("Workspace", for: .normal)
    workspaceButton.showsMenuAsPrimaryAction = true
    workspaceButton.accessibilityIdentifier = "share-probe.workspace"
    agentButton.setTitle("Agent", for: .normal)
    agentButton.showsMenuAsPrimaryAction = true
    agentButton.accessibilityIdentifier = "share-probe.agent"
    sendButton.configuration = .filled()
    sendButton.setTitle("Send", for: .normal)
    sendButton.accessibilityIdentifier = "share-probe.send"
    sendButton.addTarget(self, action: #selector(submit), for: .touchUpInside)
    closeButton.setTitle("Cancel", for: .normal)
    closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
    let header = UIStackView(arrangedSubviews: [title, closeButton])
    header.distribution = .equalSpacing
    let stack = UIStackView(arrangedSubviews: [header, workspaceButton, agentButton, editor, status, sendButton])
    stack.axis = .vertical
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -16),
      editor.heightAnchor.constraint(equalToConstant: 160),
    ])
    for button in [workspaceButton, agentButton, sendButton, closeButton] {
      button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }
    runtime.onAgents = { [weak self] agents in
      guard let self else { return }
      self.connected = true
      self.agent = agents.first
      self.agentButton.setTitle(agents.first.map { "\($0.machineName) · \($0.name)" } ?? "No agent available", for: .normal)
      self.agentButton.menu = UIMenu(children: agents.map { agent in
        UIAction(title: "\(agent.machineName) · \(agent.name)") { [weak self] _ in
          self?.agent = agent
          self?.agentButton.setTitle("\(agent.machineName) · \(agent.name)", for: .normal)
          self?.updateSend()
        }
      })
      self.status.text = "Creates a new Chat session using the agent’s defaults. The containing app is not involved in sending."
      self.updateSend()
    }
    runtime.onFailure = { [weak self] in
      guard let self else { return }
      self.connected = false
      if !self.attempted { self.status.text = "Unable to connect. Close and try sharing again. Your text is still here." }
      self.updateSend()
    }
    ingest()
    updateSend()
    status.text = "Checking the Lody app’s login…"
    task = Task { [weak self] in
      guard let self else { return }
      do {
        let workspaces = try await self.runtime.authenticate()
        guard !Task.isCancelled else { return }
        self.workspaces = workspaces
        self.workspaceButton.menu = UIMenu(children: workspaces.map { workspace in
          UIAction(title: workspace.name) { [weak self] _ in self?.select(workspace) }
        })
        if let workspace = workspaces.first { self.select(workspace) }
        else { self.status.text = "No workspace available." }
      } catch {
        if !Task.isCancelled { self.status.text = "Sign in to the Lody iOS app first, then share again. No desktop credentials are used." }
      }
    }
  }

  private func select(_ workspace: ShareProbeRuntime.Workspace) {
    guard !attempted else { return }
    connected = false
    agent = nil
    workspaceId = workspace.id
    workspaceButton.setTitle(workspace.name, for: .normal)
    agentButton.setTitle("Loading agents…", for: .normal)
    agentButton.menu = nil
    status.text = "Connecting to workspace…"
    updateSend()
    do { try runtime.start(workspaceId: workspace.id) }
    catch { status.text = "Unable to start the bundled runtime." }
  }

  private func ingest() {
    let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
    let providers = items.flatMap { $0.attachments ?? [] }.filter {
      $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
    }
    loadingItems = providers.count
    for (index, provider) in providers.enumerated() {
      let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url : .plainText
      provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { [weak self] value, _ in
        let text: String
        if let url = value as? URL, !url.isFileURL { text = url.absoluteString }
        else if let value = value as? String { text = value }
        else { text = "" }
        Task { @MainActor [weak self] in
          guard let self else { return }
          self.sharedText[index] = text
          self.loadingItems -= 1
          if self.loadingItems == 0 {
            var seen = Set<String>()
            self.editor.text = self.sharedText.sorted { $0.key < $1.key }.map(\.value)
              .filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: "\n\n")
          }
          self.updateSend()
        }
      }
    }
  }

  func textViewDidChange(_ textView: UITextView) { updateSend() }
  private func updateSend() {
    let text = editor.text.trimmingCharacters(in: .whitespacesAndNewlines)
    sendButton.isEnabled = connected && !attempted && loadingItems == 0 && agent != nil && !text.isEmpty && text.utf8.count <= 64 * 1024
    editor.isEditable = !attempted && loadingItems == 0
    workspaceButton.isEnabled = !attempted
    agentButton.isEnabled = connected && !attempted
  }

  private func persist(_ attempt: ShareProbeAttempt) throws {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "LodyShareAppGroup") as? String,
      let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
      throw NSError(domain: "LodyShareProbe", code: 1)
    }
    let directory = root.appendingPathComponent("Library/LodyShareProbe", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(attempt)
    try data.write(to: directory.appendingPathComponent(attempt.sessionId + ".json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  @objc private func submit() {
    guard sendButton.isEnabled, let agent else { return }
    attempted = true
    updateSend()
    closeButton.setTitle("Close", for: .normal)
    editor.resignFirstResponder()
    status.text = "Creating session and sending…"
    task = Task { [weak self] in
      guard let self else { return }
      var attempt = ShareProbeAttempt(userId: self.runtime.userId, workspaceId: self.workspaceId, agent: agent, text: self.editor.text.trimmingCharacters(in: .whitespacesAndNewlines))
      do {
        try await self.runtime.validateAccount()
        let phase = try await attempt.submit(command: self.runtime.command, persist: self.persist)
        switch phase {
        case .accepted:
          self.status.text = "Machine acknowledged the first message.\nSession: \(attempt.sessionId)"
        case .uploaded:
          self.status.text = "Message uploaded; machine acknowledgement is unconfirmed. Open Lody to inspect it. Do not resend.\nSession: \(attempt.sessionId)"
        case .failed:
          self.status.text = "Creation or sending failed. The attempt is saved for inspection.\nSession: \(attempt.sessionId)"
        default:
          self.status.text = "Outcome unknown. Open Lody to inspect it. Do not resend.\nSession: \(attempt.sessionId)"
        }
      } catch {
        self.status.text = "Could not confirm delivery. The text is retained here; inspect Lody before sending again.\nSession: \(attempt.sessionId)"
      }
      self.runtime.stop()
      // Keep the receipt visible in the spike, so an observer can verify the ACK.
    }
  }

  @objc private func close() {
    task?.cancel()
    runtime.stop()
    extensionContext?.completeRequest(returningItems: nil)
  }
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    task?.cancel()
    runtime.stop()
  }
}
