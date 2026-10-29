import LodyCore
import Foundation

extension CreateModelOptions {
  static func sections(_ capability: Capability, _ value: ModelChoice, tab: String) -> [LodyListSection] {
    if tab == "permission" || tab == "more" {
      return visibleOptions(capability, tab: tab).map { option in
        let selected = value.configOptionValues?[option.id]
        var rows: [LodyListRow] = [.item(
          configRowId(option.id, defaultId), text("model.useDefault"), image: selected == nil ? "checkmark" : "")]
        if option.type == "boolean" {
          rows.append(.item(option.id, configTitle(option), toggle: (selected ?? option.currentValue) == .bool(true)))
        } else {
          rows += option.options.map { item in
            .item(
              configRowId(option.id, item.id), configValueTitle(option, item.id), subtitle: item.description ?? "",
              image: selected == .string(item.id) ? "checkmark" : "")
          }
        }
        return .group(option.id, header: configTitle(option), footer: option.description ?? "", rows)
      }
    }
    let rows: [(id: String, title: String, subtitle: String, selected: Bool)]
    switch tab {
    case "effort":
      rows = [(defaultId, text("model.useDefault"), "", value.effort == nil)]
        + CreateLogic.effortsFor(capability, modelId: value.modelId).map { ($0, $0, "", $0 == value.effort) }
    case "mode":
      rows = [(defaultId, text("model.useDefault"), "", value.modeId == nil)]
        + capability.modes.map { ($0.id, $0.name, $0.description ?? "", $0.id == value.modeId) }
    default:
      rows = [(defaultId, text("model.useDefault"), "", value.modelId == nil)]
        + capability.models.map { ($0.id, $0.name, $0.description ?? "", $0.id == value.modelId) }
    }
    let footers = ["effort": "model.footer.effort", "mode": "model.footer.mode"]
    return [.group(tab, footer: text(footers[tab] ?? "model.footer.model"), rows.map {
      .item($0.id, $0.title, subtitle: $0.subtitle, image: $0.selected ? "checkmark" : "")
    })]
  }
}
