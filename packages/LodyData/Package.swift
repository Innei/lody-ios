// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "LodyData",
  defaultLocalization: "en",
  platforms: [.iOS("26.0"), .macOS("26.0")],
  products: [.library(name: "LodyData", targets: ["LodyData"])],
  dependencies: [
    .package(path: "../lody-core"),
    .package(path: "../chat-kit"),
    .package(url: "https://github.com/Lakr233/MarkdownView.git", exact: "4.6.5"),
  ],
  targets: [
    .target(
      name: "LodyData",
      dependencies: [
        .product(name: "LodyCore", package: "lody-core"),
        .product(name: "LodyRuntime", package: "lody-core"),
        .product(name: "MarkdownParser", package: "MarkdownView"),
        .product(name: "ChatKitCore", package: "chat-kit"),
      ],
      path: "Sources",
      resources: [.process("Resources")]
    ),
    .testTarget(name: "LodyDataTests", dependencies: ["LodyData"], path: "Tests"),
  ]
)
