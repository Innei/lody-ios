import Foundation

enum MacVerifyRoute: Equatable {
  case scene(String)
  case reset
  case appearance(String)
  case dump(URL)
  case act(Int, MacVerifyAction)

  static let scheme = "lodymacverify"

  init?(_ url: URL) {
    guard url.scheme == Self.scheme, let host = url.host else { return nil }
    let parts = url.pathComponents.filter { $0 != "/" }
    switch host {
    case "case":
      guard parts.count == 1, let name = parts.first,
            name.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else { return nil }
      self = .scene(name)
    case "reset" where parts.isEmpty:
      self = .reset
    case "appearance":
      guard parts.count == 1, let mode = parts.first, ["light", "dark", "system"].contains(mode) else { return nil }
      self = .appearance(mode)
    case "dump" where parts.isEmpty:
      let out = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "out" }?.value
      guard let out, out.hasPrefix("/"), out.hasSuffix(".json"), !out.contains("/../") else { return nil }
      self = .dump(URL(fileURLWithPath: out))
    case "act":
      let query = Dictionary(
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
      ) { first, _ in first }
      guard parts.count == 1, let seq = query["seq"].flatMap(Int.init), let action = MacVerifyAction(parts[0], query) else { return nil }
      self = .act(seq, action)
    default:
      return nil
    }
  }
}

enum MacVerifyAction: Equatable {
  case click(String)
  case choose(current: String, option: String)
  case type(field: String, text: String)
  case key(String)

  init?(_ verb: String, _ query: [String: String]) {
    switch verb {
    case "click":
      guard let text = query["text"], !text.isEmpty else { return nil }
      self = .click(text)
    case "choose":
      guard let current = query["current"], let option = query["option"] else { return nil }
      self = .choose(current: current, option: option)
    case "type":
      guard let field = query["field"], let text = query["text"] else { return nil }
      self = .type(field: field, text: text)
    case "key":
      guard query["name"] == "return" else { return nil }
      self = .key("return")
    default:
      return nil
    }
  }
}
