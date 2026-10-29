import LodyCore
import Foundation

public enum CreateModelOptions: Sendable {
  public static let defaultId = "lody:default"

  public static func text(_ key: String) -> String { String(localized: String.LocalizationValue(key), bundle: .lodyData) }

  public static func isPermission(_ option: ConfigOption) -> Bool {
    option.category == "_permission" || option.id == "permission_mode"
  }

  public static func configRowId(_ id: String, _ value: String) -> String { "config:\(id):\(value)" }

  public static func configTitle(_ option: ConfigOption) -> String {
    let titles = [
      "permission_mode": "model.tab.permission", "fast-mode": "model.config.fast", "fast": "model.config.fast",
      "collaboration_mode": "model.config.collaboration", "agent_preset": "model.config.preset",
    ]
    return titles[option.id].map(text) ?? option.name
  }

  public static func configValueTitle(_ option: ConfigOption, _ id: String) -> String {
    if isPermission(option) {
      let labels = [
        "ask": "model.permission.ask", "auto": "model.permission.auto",
        "always-approve": "model.permission.alwaysApprove",
      ]
      if let key = labels[id] { return text(key) }
    }
    return option.options.first { $0.id == id }?.name ?? id
  }

  public static func hasTabs(_ capability: Capability) -> Bool {
    !capability.modes.isEmpty || !capability.reasoningEfforts.isEmpty
      || !CreateLogic.effortsFor(capability).isEmpty || !CreateLogic.extraConfigOptions(capability).isEmpty
  }

  public static func summary(_ capability: Capability, _ value: ModelChoice) -> String {
    let model = capability.models.first { $0.id == value.modelId }
    let mode = capability.modes.first { $0.id == value.modeId }
    let extras = CreateLogic.extraConfigOptions(capability).compactMap { option -> String? in
      switch value.configOptionValues?[option.id] {
      case .bool(let flag): "\(configTitle(option)): \(text(flag ? "model.config.on" : "model.config.off"))"
      case .string(let id): configValueTitle(option, id)
      case nil: nil
      }
    }
    return ([model?.name ?? text("model.default"), value.effort, mode?.name] + extras)
      .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
  }

  public static func tabs(_ capability: Capability, _ value: ModelChoice) -> [(id: String, title: String)] {
    let extras = CreateLogic.extraConfigOptions(capability)
    var tabs = [("model", text("model.tab.model"))]
    if !CreateLogic.effortsFor(capability, modelId: value.modelId).isEmpty { tabs.append(("effort", text("model.tab.effort"))) }
    if !capability.modes.isEmpty { tabs.append(("mode", text("model.tab.mode"))) }
    if extras.contains(where: isPermission) { tabs.append(("permission", text("model.tab.permission"))) }
    if extras.contains(where: { !isPermission($0) }) { tabs.append(("more", text("model.tab.more"))) }
    return tabs
  }

  public static func visibleOptions(_ capability: Capability, tab: String) -> [ConfigOption] {
    CreateLogic.extraConfigOptions(capability).filter { tab == "permission" ? isPermission($0) : !isPermission($0) }
  }

  public static func toggled(_ value: ModelChoice, id: String, on: Bool) -> ModelChoice {
    setConfig(value, id: id, to: .bool(on))
  }

  // Returns nil for a model pick: switching models restores that model's remembered choice.
  public static func pressed(_ capability: Capability, _ value: ModelChoice, tab: String, id: String) -> ModelChoice? {
    if tab == "permission" || tab == "more" {
      for option in visibleOptions(capability, tab: tab) {
        if id == configRowId(option.id, defaultId) { return setConfig(value, id: option.id, to: nil) }
        if let item = option.options.first(where: { id == configRowId(option.id, $0.id) }) {
          return setConfig(value, id: option.id, to: .string(item.id))
        }
      }
      return value
    }
    let picked = id == defaultId ? nil : id
    var next = value
    switch tab {
    case "effort": next.effort = picked
    case "mode": next.modeId = picked
    default: return nil
    }
    return next
  }

  private static func setConfig(_ value: ModelChoice, id: String, to selected: ConfigValue?) -> ModelChoice {
    var next = value
    var values = value.configOptionValues ?? [:]
    values[id] = selected
    next.configOptionValues = values
    return next
  }
}
