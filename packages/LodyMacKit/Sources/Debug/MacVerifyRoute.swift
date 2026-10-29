import Foundation

enum MacVerifyRoute: Equatable {
  case scene(String)
  case reset
  case appearance(String)
  case dump(URL)

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
    default:
      return nil
    }
  }
}
