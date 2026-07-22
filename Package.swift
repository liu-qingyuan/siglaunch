// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Siglaunch",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .library(name: "SiglaunchCore", targets: ["SiglaunchCore"]),
    .executable(name: "Siglaunch", targets: ["SiglaunchApp"]),
  ],
  targets: [
    .target(name: "SiglaunchCore"),
    .executableTarget(
      name: "SiglaunchApp",
      dependencies: ["SiglaunchCore"]
    ),
    .testTarget(
      name: "SiglaunchCoreTests",
      dependencies: ["SiglaunchCore"]
    ),
    .testTarget(
      name: "SiglaunchAppTests",
      dependencies: ["SiglaunchApp", "SiglaunchCore"],
      resources: [.process("Fixtures")]
    ),
  ]
)
