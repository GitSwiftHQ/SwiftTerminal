// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftTerminal",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "SwiftTerminal",
            targets: ["SwiftTerminal"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftTerminal",
            resources: [
                .copy("Resources/TerminalRuntime"),
                .copy("Resources/TerminalThemes"),
            ]
        ),
        .testTarget(
            name: "SwiftTerminalTests",
            dependencies: ["SwiftTerminal"]
        ),
    ]
)
