// swift-tools-version:5.10
import PackageDescription
let package = Package(
    name: "OneSync",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "OneSync", path: "Sources/OneSync")]
)
