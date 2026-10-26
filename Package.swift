// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "LocalLedger", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name: "LedgerCore", targets: ["LedgerCore"])], targets: [.target(name: "LedgerCore"), .testTarget(name: "LedgerCoreTests", dependencies: ["LedgerCore"])])
