import Foundation

struct ChatComposerOption: Decodable {
  let id: String
  let title: String
  var description: String?
}

struct ChatComposerOptions: Decodable {
  var modelId = ""
  var effort = ""
  var permissionId: String?
  var permissions: [ChatComposerOption]?
  var fast: Bool?
  var models: [ChatComposerOption] = []
  var efforts: [ChatComposerOption] = []
}

extension ChatComposerOptions {
  var modelTitle: String {
    models.first { $0.id == modelId }?.title
      ?? (modelId.isEmpty ? String(localized: "native.chat.composer.defaultModel", bundle: .lody) : modelId)
  }
  var effortTitle: String {
    let title = efforts.first { $0.id == effort }?.title ?? effort
    switch title.lowercased() {
    case "": return String(localized: "native.chat.composer.defaultEffort", bundle: .lody)
    case "xhigh": return "Extra High"
    default: return title.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }

  var orderedEfforts: [ChatComposerOption] {
    let rank = [
      "off": 0, "none": 0, "minimal": 1, "low": 2, "medium": 3, "high": 4, "xhigh": 5, "max": 6, "ultra": 7,
    ]
    return efforts.enumerated().sorted { lhs, rhs in
      let left = rank[lhs.element.id.lowercased()]
      let right = rank[rhs.element.id.lowercased()]
      if let left, let right { return left < right }
      if left != nil { return true }
      if right != nil { return false }
      return lhs.offset < rhs.offset
    }.map(\.element)
  }
}
