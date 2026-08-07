// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TodoPanel",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TodoPanel",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
