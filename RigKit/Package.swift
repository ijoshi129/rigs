// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RigKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "RigKit", targets: ["RigKit"]),
    ],
    targets: [
        .target(name: "RigKit"),
        .testTarget(name: "RigKitTests", dependencies: ["RigKit"]),
    ],
    swiftLanguageModes: [.v6]
)
