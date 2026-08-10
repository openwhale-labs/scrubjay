// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ScrubJay",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "ScrubJayKit", targets: ["ScrubJayKit"]),
    .executable(name: "scrubjay", targets: ["ScrubJayCLI"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.2")
  ],
  targets: [
    .target(name: "ScrubJayKit"),
    .executableTarget(
      name: "ScrubJayCLI",
      dependencies: [
        "ScrubJayKit",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(name: "ScrubJayKitTests", dependencies: ["ScrubJayKit"]),
  ]
)
