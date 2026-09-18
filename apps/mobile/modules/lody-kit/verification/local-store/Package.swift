// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "LocalStoreVerification",
  platforms: [.macOS(.v13)],
  dependencies: [.package(url: "https://github.com/Lakr233/MarkdownView.git", exact: "4.3.2")],
  targets: [.executableTarget(
    name: "LocalStoreVerification",
    dependencies: [.product(name: "MarkdownParser", package: "MarkdownView")],
    path: "Sources",
    linkerSettings: [.linkedLibrary("sqlite3")]
  )]
)
