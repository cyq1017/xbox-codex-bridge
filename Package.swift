// swift-tools-version: 5.10

import PackageDescription

let package = Package(
  name: "XboxCodexBridge",
  platforms: [.macOS(.v13)],
  products: [
    .library(name: "XboxCodexBridgeCore", targets: ["XboxCodexBridgeCore"]),
    .executable(name: "XboxCodexBridge", targets: ["XboxCodexBridge"]),
  ],
  targets: [
    .target(name: "XboxCodexBridgeCore"),
    .executableTarget(
      name: "XboxCodexBridge",
      dependencies: ["XboxCodexBridgeCore"],
      resources: [.copy("Web")]
    ),
    .testTarget(
      name: "XboxCodexBridgeCoreTests",
      dependencies: ["XboxCodexBridgeCore"]
    ),
    .testTarget(
      name: "XboxCodexBridgeTests",
      dependencies: ["XboxCodexBridge"]
    ),
  ]
)
