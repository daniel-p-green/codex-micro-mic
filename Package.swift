// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "CodexMic",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "CodexMic", targets: ["CodexMic"]),
    .executable(name: "CodexMicChecks", targets: ["CodexMicChecks"]),
  ],
  targets: [
    .target(name: "CodexMicCore"),
    .executableTarget(
      name: "CodexMic",
      dependencies: ["CodexMicCore"],
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("AVFoundation"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("Carbon"),
        .linkedFramework("Network"),
      ]
    ),
    .executableTarget(
      name: "CodexMicChecks",
      dependencies: ["CodexMicCore"]
    ),
  ]
)
