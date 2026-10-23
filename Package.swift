// swift-tools-version: 6.0

import PackageDescription

let linkerFlags: [LinkerSetting] = [
    .unsafeFlags([
        // Safari finds each extension's handler class by name (NSExtensionPrincipalClass),
        // so nothing in the code references it and the linker would drop it. -ObjC keeps it.
        "-Xlinker", "-ObjC",
        // Leave room in the binary header for the code signature added when signing.
        "-Xlinker", "-headerpad_max_install_names",
    ]),
]

let package = Package(
    name: "uKivi",
    platforms: [.iOS(.v17)],
    products: [
        // The app itself
        .library(name: "uKivi", targets: ["uKivi"]),
        // Safari Content Blockers (one per filter group, each can hold 150k rules).
        // Kept to two: free Apple accounts can only create 10 App IDs a week.
        .library(name: "uKiviAds", targets: ["uKiviAds"]),
        .library(name: "uKiviPrivacy", targets: ["uKiviPrivacy"]),
        // Safari Web Extension (element hider, per-site pause, YouTube fixes)
        .library(name: "uKiviWebExtension", targets: ["uKiviWebExtension"]),
    ],
    dependencies: [
        // Filter list converter, shared with the Linux tooling (see Packages/FilterKit).
        .package(path: "Packages/FilterKit"),
    ],
    targets: [
        .target(name: "uKiviShared"),
        .target(
            name: "uKivi",
            dependencies: ["uKiviShared", .product(name: "FilterKit", package: "FilterKit")],
            linkerSettings: linkerFlags
        ),
        .target(name: "uKiviAds", dependencies: ["uKiviShared"], linkerSettings: linkerFlags),
        .target(name: "uKiviPrivacy", dependencies: ["uKiviShared"], linkerSettings: linkerFlags),
        .target(name: "uKiviWebExtension", dependencies: ["uKiviShared"], linkerSettings: linkerFlags),
    ],
    swiftLanguageModes: [.v5]
)
