import Foundation

enum LodyStrings {
  static func text(_ key: String, _ vars: [String: CustomStringConvertible] = [:]) -> String {
    substitute(entry(key), vars)
  }

  static func plural(_ key: String, _ count: Int, _ vars: [String: CustomStringConvertible] = [:]) -> String {
    substitute(String.localizedStringWithFormat(entry(key), count), vars)
  }

  private static func entry(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
  }

  /// One left-to-right pass, so a substituted value is never rescanned for placeholders.
  static func substitute(_ template: String, _ vars: [String: CustomStringConvertible]) -> String {
    guard template.contains("{"), !vars.isEmpty else { return template }
    var result = ""
    var rest = Substring(template)
    while let open = rest.firstIndex(of: "{") {
      guard let close = rest[open...].firstIndex(of: "}") else { break }
      let name = String(rest[rest.index(after: open)..<close])
      result += rest[rest.startIndex..<open]
      result += vars[name].map { String(describing: $0) } ?? "{\(name)}"
      rest = rest[rest.index(after: close)...]
    }
    return result + rest
  }
}
