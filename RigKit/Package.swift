// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RigKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RigKit", targets: ["RigKit"]),
    ],
    targets: [
        .target(name: "RigKit"),
        .testTarget(name: "RigKitTests", dependencies: ["RigKit"]),
    ],
    swiftLanguageModes: [.v6]
)
