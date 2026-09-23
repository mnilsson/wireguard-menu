// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WireGuardMenu",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "WireGuardCore"),
        .executableTarget(name: "WireGuardMenu", dependencies: ["WireGuardCore"]),
        .executableTarget(name: "WireGuardHelper", dependencies: ["WireGuardCore"]),
        .testTarget(name: "WireGuardMenuTests", dependencies: ["WireGuardMenu", "WireGuardCore", "WireGuardHelper"])
    ]
)
