// swift-tools-version:5.9
import PackageDescription

// The module is named GS1DataMatrixKit so that the public `GS1DataMatrix`
// entry point type does not collide with the module name.
let package = Package(
    name: "GS1DataMatrixKit",
    products: [
        .library(name: "GS1DataMatrixKit", targets: ["GS1DataMatrixKit"]),
        .executable(name: "gs1dm", targets: ["gs1dm"]),
    ],
    targets: [
        // Pure Swift standard library. No Foundation, no external dependencies.
        .target(name: "GS1DataMatrixKit", path: "Sources/GS1DataMatrix"),
        .executableTarget(name: "gs1dm", dependencies: ["GS1DataMatrixKit"]),
        .testTarget(name: "GS1DataMatrixKitTests", dependencies: ["GS1DataMatrixKit"]),
    ]
)
