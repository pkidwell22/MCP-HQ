// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MCPHQ",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MCPHQCore", targets: ["MCPHQCore"]),
        .executable(name: "mcphq", targets: ["MCPHQCLI"]),
        .executable(name: "MCPHQApp", targets: ["MCPHQApp"]),
    ],
    targets: [
        .target(name: "MCPHQCore", linkerSettings: [.linkedLibrary("sqlite3"), .linkedFramework("Security")]),
        .executableTarget(name: "MCPHQCLI", dependencies: ["MCPHQCore"]),
        .executableTarget(name: "MCPHQApp", dependencies: ["MCPHQCore"]),
        .testTarget(name: "MCPHQCoreTests", dependencies: ["MCPHQCore"], resources: [.copy("Fixtures")]),
    ]
)
