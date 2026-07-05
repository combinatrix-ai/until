// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "Until",
  defaultLocalization: "en",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "Until", targets: ["Until"])
  ],
  targets: [
    .executableTarget(name: "Until"),
    .testTarget(name: "UntilTests", dependencies: ["Until"])
  ]
)
