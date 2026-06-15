// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Winamp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Winamp", targets: ["Winamp"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Winamp",
            dependencies: [],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        )
    ]
)

