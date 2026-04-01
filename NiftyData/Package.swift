// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NiftyData",
    // iOS 16 satisfies all transitive SPM dependencies (GRDB requires ≥13).
    // The actual deployment target (iOS 26) is enforced by the Xcode project settings.
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "NiftyData", targets: ["NiftyData"]),
    ],
    dependencies: [
        .package(path: "../NiftyCore"),
        // GRDB for SQLite access. SQLCipher AES-256 encryption (SRS §7.2) will be added
        // once a compatible SQLCipher SPM package is identified — GRDBSQLCipher was removed
        // from the GRDB.swift package in v7. For now, the database runs unencrypted with
        // WAL mode; the KeychainBridge key-generation path is retained for when we wire it.
        .package(url: "https://github.com/groue/GRDB.swift", .upToNextMajor(from: "7.0.0")),
    ],
    targets: [
        .target(
            name: "NiftyData",
            dependencies: [
                "NiftyCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "NiftyDataTests",
            dependencies: ["NiftyData", "NiftyCore"],
            path: "Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
