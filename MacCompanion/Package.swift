// swift-tools-version: 6.0
import PackageDescription

// The Mac companion deliberately depends only on the Foundation-only
// IssueCaptureSchema product. It never links the iOS IssueCapture target, which
// imports UIKit and hosts capture, recording and disabled-host behavior.
let package = Package(
    name: "IssueCaptureCompanion",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "IssueCaptureCompanion", targets: ["IssueCaptureCompanion"]),
        .library(name: "CompanionCore", targets: ["CompanionCore"])
    ],
    dependencies: [.package(name: "IssueCapture", path: "..")],
    targets: [
        .target(name: "CompanionCore",
                dependencies: [.product(name: "IssueCaptureSchema", package: "IssueCapture")]),
        .executableTarget(name: "IssueCaptureCompanion", dependencies: ["CompanionCore"]),
        .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"])
    ],
    swiftLanguageModes: [.v5]
)
