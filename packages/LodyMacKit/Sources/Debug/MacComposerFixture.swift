import Foundation
import LodyCore
import LodyData

@MainActor
enum MacComposerFixture {
  static let capability = Capability(
    machineId: "m-studio", cliType: "builtin", agentType: "claude",
    models: [CapabilityChoice(id: "opus", name: "Opus 5.5"), CapabilityChoice(id: "sonnet", name: "Sonnet 5.5")],
    modes: [CapabilityChoice(id: "default", name: "Ask first"), CapabilityChoice(id: "acceptEdits", name: "Accept edits"),
            CapabilityChoice(id: "bypassPermissions", name: "Full access")],
    reasoningEfforts: ["opus": ["low", "medium", "high"], "sonnet": ["low", "medium", "high"]]
  )

  static var service: MacComposerService {
    MacComposerService(
      options: { _, projectId in
        guard projectId != "p-docs" else { return CreationOptions(sessionId: "s-new", agents: [], capabilities: []) }
        let agents = [
          CreationAgent(id: "claude", name: "Claude Code", machineId: "m-studio", machineName: "Mac Studio", cliType: "builtin", agentType: "claude"),
          CreationAgent(id: "codex", name: "Codex", machineId: "m-mini", machineName: "Mac mini", cliType: "builtin", agentType: "codex"),
        ]
        var codex = capability
        codex.machineId = "m-mini"
        codex.agentType = "codex"
        return CreationOptions(sessionId: "s-new", agents: agents, capabilities: [capability, codex])
      },
      create: { _, _ in }
    )
  }
}
