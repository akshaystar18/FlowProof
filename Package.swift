// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlowProof",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FlowProof", targets: ["FlowProof"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "FlowProof",
            dependencies: [
                "Yams",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/FlowProof"
        ),
        .testTarget(
            name: "FlowProofTests",
            dependencies: ["FlowProof"],
            path: "Tests/FlowProofTests"
        ),
    ]
)
