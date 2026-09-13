// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IssueCapture",
    platforms: [.iOS(.v17)],
    products: [.library(name: "IssueCapture", targets: ["IssueCapture"])],
    targets: [.target(name: "IssueCapture")],
    swiftLanguageModes: [.v5]
)
