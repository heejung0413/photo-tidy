// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhotoTidyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PhotoTidyCore", targets: ["PhotoTidyCore"])],
    targets: [
        .target(name: "PhotoTidyCore"),
        .testTarget(name: "PhotoTidyCoreTests", dependencies: ["PhotoTidyCore"]),
    ]
)
