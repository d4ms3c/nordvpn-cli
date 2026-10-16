// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "nordvpn-cli",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "nordvpn", targets: ["nordvpn"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "NordVPNKit",
            linkerSettings: [.linkedFramework("SystemConfiguration"), .linkedFramework("AppKit")]
        ),
        .target(name: "NordVPNMCP", dependencies: ["NordVPNKit"]),
        .executableTarget(
            name: "nordvpn",
            dependencies: [
                "NordVPNKit",
                "NordVPNMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "NordVPNKitTests", dependencies: ["NordVPNKit"]),
        .testTarget(name: "NordVPNMCPTests", dependencies: ["NordVPNMCP", "NordVPNKit"]),
    ]
)
