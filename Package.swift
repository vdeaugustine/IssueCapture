// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IssueCapture",
    // IssueCaptureSchema is Foundation-only and supports macOS readers such as
    // the Mac companion. The IssueCapture target itself remains an iOS UIKit
    // library and is not buildable for macOS.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "IssueCapture", targets: ["IssueCapture"]),
        .library(name: "IssueCaptureSchema", targets: ["IssueCaptureSchema"])
    ],
    targets: [
        .target(name: "IssueCaptureSchema"),
        .target(name: "IssueCapture", dependencies: ["IssueCaptureSchema"])
    ],
    swiftLanguageModes: [.v5]
)
