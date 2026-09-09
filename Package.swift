// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HiddenStart",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "HiddenStart",
            targets: ["HiddenStart"]
        )
    ],
    targets: [
        .executableTarget(
            name: "HiddenStart",
            path: "HiddenStart/Sources"
        ),
        .testTarget(
            name: "HiddenStartTests",
            dependencies: ["HiddenStart"],
            path: "HiddenStartTests"
        )
    ]
)
