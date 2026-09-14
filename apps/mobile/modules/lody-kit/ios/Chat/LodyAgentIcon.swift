import Foundation

enum LodyAgentIcon {
  private static let kinds: Set<String> = [
    "claude", "codex", "kimi", "grok", "deepseek", "minimax", "glm", "mimo", "opencode", "gemini", "openai",
  ]
  private static let aliases: [String: String] = [
    "claude-p": "claude",
    "kimi-code": "kimi",
    "anthropic": "claude",
    "sonnet": "claude",
    "opus": "claude",
    "haiku": "claude",
    "chatgpt": "openai",
    "gpt": "openai",
    "o1": "openai",
    "o3": "openai",
    "o4": "openai",
    "xai": "grok",
    "gemma": "gemini",
    "moonshot": "kimi",
    "zhipu": "glm",
    "chatglm": "glm",
  ]

  static func asset(modelId: String?, name: String?) -> String? {
    for raw in [modelId, name] {
      guard let raw else { continue }
      let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if value.isEmpty { continue }
      if let asset = asset(for: value) { return asset }
      for token in value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
        if let asset = asset(for: String(token)) { return asset }
      }
    }
    return nil
  }

  private static func asset(for kind: String) -> String? {
    let canonical = aliases[kind] ?? kind
    return kinds.contains(canonical) ? "lody-agent-\(canonical)" : nil
  }
}
