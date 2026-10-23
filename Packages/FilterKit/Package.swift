// swift-tools-version: 6.0

import PackageDescription

// Converts uBlock Origin / Adblock Plus filter lists into Safari content blocker rules.
// Used by the app for on-device updates. Pure Foundation, so it builds and tests on Linux:
//   cd Packages/FilterKit && swift test
let package = Package(
    name: "FilterKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FilterKit", targets: ["FilterKit"]),
        .executable(name: "filterkit", targets: ["filterkit"]),
    ],
    targets: [
        .target(name: "FilterKit"),
        // Command-line tool, used to check the output matches Tools/convert_filters.py.
        .executableTarget(name: "filterkit", dependencies: ["FilterKit"]),
        .testTarget(name: "FilterKitTests", dependencies: ["FilterKit"]),
    ]
)
