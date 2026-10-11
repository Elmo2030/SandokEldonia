// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IPTVMac",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // Reusable by both apps: the macOS app (this package) and the iPhone/iPad app (ios/project.yml).
        .library(name: "IPTVCore", targets: ["IPTVCore"]),
        .library(name: "IPTVPlayer", targets: ["IPTVPlayer"]),
        .library(name: "IPTVAppKit", targets: ["IPTVAppKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .systemLibrary(name: "CLibMPV", pkgConfig: "mpv", providers: [.brew(["mpv"])]),
        // iOS: the same C API from the media-kit iOS headers (no pkg-config); the symbols come from the Mpv.xcframework the Xcode app links.
        .target(name: "CLibMPViOS"),
        .target(name: "IPTVPlayer", dependencies: [
            .target(name: "CLibMPV", condition: .when(platforms: [.macOS])),
            .target(name: "CLibMPViOS", condition: .when(platforms: [.iOS])),
        ]),
        .target(name: "IPTVCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        // Platform-neutral app state and logic (accounts, search, sync, favorites, backup), shared by the macOS and iOS apps.
        .target(name: "IPTVAppKit", dependencies: ["IPTVCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .executableTarget(
            name: "IPTVMac",
            dependencies: ["IPTVCore", "IPTVPlayer", "IPTVAppKit"],
            resources: [.process("Resources")]
        ),
        // ponytail: Command Line Tools only: the swift-testing macro plugin is not found on rebuilds without this flag.
        .testTarget(name: "IPTVCoreTests", dependencies: ["IPTVCore"],
                    swiftSettings: [.unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])]),
        .testTarget(name: "IPTVPlayerTests", dependencies: ["IPTVPlayer"],
                    swiftSettings: [.unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])]),
        .testTarget(name: "IPTVAppKitTests", dependencies: ["IPTVAppKit", "IPTVCore"],
                    swiftSettings: [.unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])]),
        .testTarget(name: "IPTVMacTests", dependencies: ["IPTVMac"],
                    swiftSettings: [.unsafeFlags(["-plugin-path", "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"])]),
    ],
    swiftLanguageModes: [.v5]
)
