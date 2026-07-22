// swift-tools-version: 6.0

import PackageDescription

let cameraUsageLinkerSettings: [LinkerSetting] = [
  .unsafeFlags(
    [
      "-Xlinker", "-sectcreate",
      "-Xlinker", "__TEXT",
      "-Xlinker", "__info_plist",
      "-Xlinker", "Sources/SiglaunchApp/Info.plist",
    ],
    .when(platforms: [.macOS])
  )
]

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
      dependencies: ["SiglaunchCore"],
      exclude: ["Info.plist"],
      linkerSettings: cameraUsageLinkerSettings
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
