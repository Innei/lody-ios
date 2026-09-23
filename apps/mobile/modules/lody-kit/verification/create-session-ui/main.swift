import UIKit

let controller = CreateSessionController()
controller.configure(["userId": "fixture", "workspaceId": "workspace", "context": "chat",
  "options": ["chat": ["agents": [["id": "agent", "name": "Agent", "machineId": "machine", "machineName": "Fixture Mac", "cliType": "builtin", "agentType": "codex"]], "capabilities": []]]])
controller.loadViewIfNeeded()
controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 700)
controller.busy = true
controller.composer.setInitialDraft("Shared fixture text")
controller.busy = false
controller.view.layoutIfNeeded()
@MainActor func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
let send = descendants(controller.view).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-send" }!
precondition(send.isEnabled, "The shared form must pass a complete decodable composer state")
var submitted: [String: Any]?
controller.onSubmit = { submitted = $0 }
controller.composer.perform(NSSelectorFromString("submit"))
precondition(submitted?["text"] as? String == "Shared fixture text")
precondition((submitted?["agent"] as? [String: Any])?["machineId"] as? String == "machine")
controller.busy = true; precondition(!send.isEnabled)
controller.busy = false; controller.submissionLocked = true; precondition(!send.isEnabled)
controller.submissionLocked = false
controller.busy = true; controller.busy = false
precondition(send.isEnabled, "Recovery/loading must not consume the current draft")
var rejected = false
controller.onRejected = { rejected = true }
controller.submit(["text": String(repeating: "字", count: 24000), "attachments": []])
precondition(rejected, "Oversized UTF-8 must return control to the owning composer host")
let picker = CreateSessionPicker(title: "Fixture", items: [("fixture", "Fixture")], selected: "fixture") { _ in }
picker.loadViewIfNeeded()
let cell = picker.collectionView(picker.collectionView, cellForItemAt: IndexPath(item: 0, section: 0))
precondition(cell.accessibilityIdentifier == "fixture", "Picker registration must exist before cell dequeue")
var optionForm = controller.form
optionForm.snapshot["options"] = ["chat": ["agents": optionForm.agents, "capabilities": [["machineId": "machine", "cliType": "builtin", "agentType": "codex", "models": [["id": "fixture", "name": "Fixture"]]]]]]
let options = CreateSessionOptionsController(form: optionForm) { _ in }
options.loadViewIfNeeded()
let optionCell = options.collectionView(options.collectionView, cellForItemAt: IndexPath(item: 0, section: 0))
precondition(optionCell.accessibilityIdentifier == "option-modelId")
print("PASS: production shared form enables Send, preserves target/content, disables duplicate submission and releases rejected drafts")
