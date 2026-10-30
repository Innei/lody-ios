import Foundation

@MainActor
enum LodyLicenses {
  private static var cache: LodyLicenseList?

  // A few hundred KB: decode on first open instead of at launch.
  private static var catalog: LodyLicenseList {
    if let cache { return cache }
    let loaded = LodyLicenseList.load(from: Bundle.main.url(forResource: "LodyLicenses", withExtension: "json"))
    cache = loaded
    return loaded
  }

  static var packages: [LodyLicense] { catalog.packages }

  static func entry(_ name: String) -> LodyLicense? { catalog.entry(name) }

  static func text(_ entry: LodyLicense) -> String { catalog.text(entry) }
}
