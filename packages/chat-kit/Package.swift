// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ChatKit",
  platforms: [.iOS("26.0")],
  products: [.library(name: "ChatKit", targets: ["ChatKit"])],
  targets: [
    .target(name: "ChatKitCore"),
    .target(name: "ChatKit", dependencies: ["ChatKitCore"]),
    .testTarget(name: "ChatKitCoreTests", dependencies: ["ChatKitCore"]),
  ]
)
