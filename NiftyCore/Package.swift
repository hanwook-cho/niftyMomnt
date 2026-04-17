// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NiftyCore",
    // iOS 16 declared for SPM compatibility; actual deployment target (iOS 26) is in Xcode project.
    // macOS declared so `swift test` can build on host; iOS 26 deployment target lives in the Xcode project.
    platforms: [.iOS(.v16), .macOS(.v14)],
    products: [
        .library(name: "NiftyCore", targets: ["NiftyCore"]),
    ],
    targets: [
        .target(
            name: "NiftyCore",
            // Sources span Domain/, Engines/, Managers/ under Sources/
            path: "Sources"
        ),
        .testTarget(
            name: "NifyCoreTests",
            dependencies: ["NiftyCore"],
            path: "Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
