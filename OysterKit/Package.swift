// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OysterKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "OysterKit", targets: ["OysterKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.6"),
    ],
    targets: [
        .target(name: "OysterKit"),
        .testTarget(
            name: "OysterKitTests",
            dependencies: [
                "OysterKit",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
