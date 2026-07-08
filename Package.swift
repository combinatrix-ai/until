// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "Until",
  defaultLocalization: "en",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "Until", targets: ["Until"])
  ],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
  ],
  targets: [
    .executableTarget(
      name: "Until",
      dependencies: [.product(name: "Sparkle", package: "Sparkle")]
    ),
    .testTarget(name: "UntilTests", dependencies: ["Until"])
  ]
)
