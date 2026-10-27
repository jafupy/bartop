// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "bartop",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "bartop", targets: ["bartop"])],
    targets: [
        .target(name: "SystemMetrics", linkerSettings: [.linkedFramework("IOKit")]),
        .executableTarget(name: "bartop", dependencies: ["SystemMetrics"])
    ],
    swiftLanguageModes: [.v5]
)
