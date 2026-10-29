// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "LodyMacKit",
  defaultLocalization: "en",
  platforms: [.macOS("26.0")],
  products: [.library(name: "LodyMacKit", targets: ["LodyMacKit"])],
  dependencies: [
    .package(path: "../LodyData"),
    .package(path: "../lody-core"),
    .package(url: "https://github.com/Lakr233/MarkdownView.git", exact: "4.6.5"),
  ],
  targets: [
    .target(
      name: "LodyMacKit",
      dependencies: [
        .product(name: "LodyData", package: "LodyData"),
        .product(name: "LodyCore", package: "lody-core"),
        .product(name: "MarkdownView", package: "MarkdownView"),
      ],
      resources: [.process("Resources")]
    ),
    .testTarget(name: "LodyMacKitTests", dependencies: ["LodyMacKit"]),
  ]
)
