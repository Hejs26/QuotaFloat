// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "QuotaFloat",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(name: "QuotaFloat", targets: ["QuotaFloat"])
  ],
  dependencies: [
    .package(
      url: "https://github.com/steipete/CodexBar.git",
      revision: "3f3e2f4a112aa504c493ad5636c94e45df85fd03")
  ],
  targets: [
    .executableTarget(
      name: "QuotaFloat",
      dependencies: [
        .product(name: "CodexBarCore", package: "CodexBar")
      ],
      path: "Sources/QuotaFloat",
      resources: [
        .copy("Resources/claude-mark.svg"),
        .copy("Resources/kimi-mark.svg")
      ])
  ])
