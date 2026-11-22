// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Calendesk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Calendesk", path: "Sources/Calendesk")
    ]
)
