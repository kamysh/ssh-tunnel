// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ssh-tunnel",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TunnelKit", targets: ["TunnelKit"]),
        .executable(name: "tunnelctl", targets: ["tunnelctl"]),
        .executable(name: "tunnels-askpass", targets: ["tunnels-askpass"]),
        .executable(name: "TunnelsApp", targets: ["TunnelsApp"]),
    ],
    targets: [
        // Reusable engine. UI and CLI both depend only on this.
        .target(name: "TunnelKit"),

        // GUI askpass helper: ssh execs this for any interactive prompt.
        .executableTarget(name: "tunnels-askpass"),

        // CLI driver.
        .executableTarget(name: "tunnelctl", dependencies: ["TunnelKit"]),

        // Menu-bar app (SwiftUI MenuBarExtra).
        .executableTarget(name: "TunnelsApp", dependencies: ["TunnelKit"]),
    ]
)
