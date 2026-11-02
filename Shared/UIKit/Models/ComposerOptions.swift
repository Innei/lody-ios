import Foundation

struct ChatComposerOption: Decodable {
  let id: String
  let title: String
  var description: String?
}

struct ChatComposerOptions: Decodable {
  var modelId = ""
  var effort = ""
  var inheritedModelId: String?
  var inheritedEffort: String?
  var permissionId: String?
  var permissions: [ChatComposerOption]?
  var fast: Bool?
  var models: [ChatComposerOption] = []
  var efforts: [ChatComposerOption] = []
}

extension ChatComposerOptions {
  var effectiveModelId: String { modelId.isEmpty || modelId.lowercased() == "default" ? inheritedModelId ?? "" : modelId }
  var effectiveEffort: String { effort.isEmpty || effort.lowercased() == "default" ? inheritedEffort ?? "" : effort }

  func modelTitle(for id: String) -> String {
    if id.isEmpty || id.lowercased() == "default" { return String(localized: "model.unavailable", bundle: .lody) }
    return models.first { $0.id == id }?.title ?? id
  }

  var modelTitle: String {
    modelTitle(for: effectiveModelId)
  }
  var effortTitle: String {
    effortTitle(for: effectiveEffort)
  }

  func effortTitle(for id: String) -> String {
    let title = efforts.first { $0.id == id }?.title ?? id
    switch title.lowercased() {
    case "", "default": return String(localized: "model.effortUnavailable", bundle: .lody)
    case "xhigh": return "Extra High"
    default: return title.replacingOccurrences(of: "_", with: " ").capitalized
    }
  }

  func inheritedTitle(_ value: String) -> String {
    String.localizedStringWithFormat(String(localized: "model.followAgent", bundle: .lody), value)
  }

  var orderedEfforts: [ChatComposerOption] {
    let rank = [
      "off": 0, "none": 0, "minimal": 1, "low": 2, "medium": 3, "high": 4, "xhigh": 5, "max": 6, "ultra": 7,
    ]
    return efforts.filter { $0.id.lowercased() != "default" }.enumerated().sorted { lhs, rhs in
      let left = rank[lhs.element.id.lowercased()]
      let right = rank[rhs.element.id.lowercased()]
      if let left, let right { return left < right }
      if left != nil { return true }
      if right != nil { return false }
      return lhs.offset < rhs.offset
    }.map(\.element)
  }
}
