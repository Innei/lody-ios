// swift-tools-version: 6.0
import PackageDescription

let upstream: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
  name: "Lexical",
  platforms: [.iOS("26.0")],
  products: [
    .library(name: "Lexical", targets: ["Lexical"]),
    .library(name: "LexicalListPlugin", targets: ["LexicalListPlugin"]),
    .library(name: "LexicalLinkPlugin", targets: ["LexicalLinkPlugin"]),
    .library(name: "EditorHistoryPlugin", targets: ["EditorHistoryPlugin"]),
    .library(name: "HaklexNodes", targets: ["HaklexNodes"]),
  ],
  targets: [
    .target(name: "Lexical", swiftSettings: upstream),
    .target(name: "LexicalListPlugin", dependencies: ["Lexical"], swiftSettings: upstream),
    .target(name: "LexicalLinkPlugin", dependencies: ["Lexical"], swiftSettings: upstream),
    .target(name: "EditorHistoryPlugin", dependencies: ["Lexical"], swiftSettings: upstream),
    .target(name: "HaklexNodes", dependencies: ["Lexical", "LexicalListPlugin", "LexicalLinkPlugin"]),
    .testTarget(name: "HaklexNodesTests", dependencies: ["HaklexNodes", "Lexical"]),
    .testTarget(name: "LexicalTests", dependencies: ["Lexical"], swiftSettings: upstream),
    .testTarget(name: "LexicalListPluginTests", dependencies: ["Lexical", "LexicalListPlugin"], swiftSettings: upstream),
    .testTarget(name: "LexicalLinkPluginTests", dependencies: ["Lexical", "LexicalLinkPlugin"], swiftSettings: upstream),
    .testTarget(name: "EditorHistoryPluginTests", dependencies: ["Lexical", "EditorHistoryPlugin"], swiftSettings: upstream),
  ]
)
