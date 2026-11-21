// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacTermPlus",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.9.0"),
    ],
    targets: [
        // Wrappers around the system libcurl (ships with macOS) for FTP / FTPS.
        .target(
            name: "CCurlShim",
            path: "Sources/CCurlShim",
            linkerSettings: [.linkedLibrary("curl")]
        ),
        .executableTarget(
            name: "MacTermPlus",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Citadel", package: "Citadel"),
                "CCurlShim",
            ],
            path: "Sources/MacTermPlus",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
