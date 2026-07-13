// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpectraKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpectraKit", targets: ["SpectraKit"])
    ],
    targets: [
        .target(name: "SpectraKit"),
        .testTarget(
            name: "SpectraKitTests",
            dependencies: ["SpectraKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
