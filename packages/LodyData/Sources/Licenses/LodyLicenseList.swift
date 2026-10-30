import Foundation

public struct LodyLicense: Decodable, Equatable, Sendable {
  public let name: String
  public let version: String?
  public let license: String
  public let url: String?
  public let firstParty: Bool?
  public let text: Int
}

public struct LodyLicenseList: Decodable, Equatable, Sendable {
  public let packages: [LodyLicense]
  private let texts: [String]

  public static let empty = LodyLicenseList(packages: [], texts: [])

  private init(packages: [LodyLicense], texts: [String]) {
    self.packages = packages
    self.texts = texts
  }

  public static func decode(_ data: Data) throws -> LodyLicenseList {
    try JSONDecoder().decode(LodyLicenseList.self, from: data)
  }

  public static func load(from url: URL?) -> LodyLicenseList {
    url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? decode($0) } ?? .empty
  }

  public func entry(_ name: String) -> LodyLicense? { packages.first { $0.name == name } }

  public func text(_ entry: LodyLicense) -> String {
    texts.indices.contains(entry.text) ? texts[entry.text] : ""
  }
}
