// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iOS-TTS",
    platforms: [
        .iOS(.v16),
        .macOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "iOS-TTS",
            targets: ["iOS-TTS"]),
    ],
    dependencies: [
        .package(url: "https://github.com/dhrebeniuk/RosaKit.git", from: "0.0.11"),
        .package(url: "https://github.com/Otosaku/OtosakuPOSTagger-iOS", from: "1.0.0")
        // TODO: Add espeak-ng integration in the future
    ],
    targets: [
        // Binary target for espeak-ng
        .binaryTarget(
            name: "libespeak-ng",
            path: "Sources/iOS-TTS/Espeak/libespeak-ng.xcframework"
        ),
        // C target for espeak wrapper
        .target(
            name: "EspeakWrapper",
            dependencies: ["libespeak-ng"],
            path: "Sources/EspeakWrapper",
            sources: ["EspeakWrapper.c"],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../iOS-TTS/Espeak/include")
            ]),
        // Main Swift target
        .target(
            name: "iOS-TTS",
            dependencies: [
                "RosaKit",
                "EspeakWrapper",
                .product(name: "SwiftPOSTagger", package: "OtosakuPOSTagger-iOS")
            ],
            path: "Sources/iOS-TTS",
            exclude: ["Espeak"]),
        .testTarget(
            name: "iOS-TTSTests",
            dependencies: ["iOS-TTS"]
        ),
    ]
)
