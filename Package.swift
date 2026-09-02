// swift-tools-version: 6.1

import PackageDescription

let package = Package(
  name: "Until",
  defaultLocalization: "en",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "Until", targets: ["Until"])
  ],
  traits: [
    .trait(name: "sparkle", description: "Enable Sparkle auto-updates"),
    .default(enabledTraits: ["sparkle"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/sparkle-project/Sparkle",
      from: "2.6.0",
      traits: [.trait(name: "default", condition: .when(traits: ["sparkle"]))]
    )
  ],
  targets: [
    .executableTarget(
      name: "Until",
      dependencies: [
        .product(
          name: "Sparkle",
          package: "Sparkle",
          condition: .when(traits: ["sparkle"])
        )
      ],
      swiftSettings: [
        .define("SPARKLE", .when(traits: ["sparkle"]))
      ]
    ),
    .testTarget(name: "UntilTests", dependencies: ["Until"])
  ],
  swiftLanguageModes: [.v5]
)
