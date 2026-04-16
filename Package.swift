// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Speakin",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "Speakin",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Speakin",
            exclude: ["Info.plist", "Speakin.entitlements"]
        )
    ]
)
