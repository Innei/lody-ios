// swift-tools-version: 5.9
import PackageDescription

// Isolated compatibility probe; not linked into the app or extension.
let package = Package(
  name: "ShareNativeProbe",
  platforms: [.macOS(.v13), .iOS(.v16)],
  dependencies: [.package(url: "https://github.com/loro-dev/loro-swift.git", exact: "1.13.3")],
  targets: [.executableTarget(name: "ShareNativeProbe", dependencies: [.product(name: "Loro", package: "loro-swift")], path: "Sources")]
)
