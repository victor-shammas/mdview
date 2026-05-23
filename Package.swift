// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mdview",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "mdview",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources"
        ),
    ]
)
