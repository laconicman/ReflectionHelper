// swift-tools-version: 6.0
//
// Tools version 6.0, not 6.1: it is the lowest that gives Swift 6 language mode
// and `swift test` support for Swift Testing, both of which this package uses.
// 6.1 would only add package traits (SE-0450) — there is nothing here to gate —
// while cutting off Xcode before 16.3. See docs/Design.md § Package shape.
import PackageDescription

let package = Package(
    name: "PropertyTree",
    // No `platforms:` deliberately: the module imports Foundation and nothing
    // else, so it builds anywhere Swift does — including Linux, which CI proves
    // on every push. Declaring floors here would only narrow that.
    products: [
        .library(name: "PropertyTree", targets: ["PropertyTree"])
    ],
    // No dependencies, deliberately — not even swift-docc-plugin: `xcodebuild
    // docbuild` needs no plugin, and Swift Package Index injects one itself when
    // a package doesn't declare it. Consumers resolve nothing but PropertyTree.
    targets: [
        .target(name: "PropertyTree"),
        .testTarget(name: "PropertyTreeTests", dependencies: ["PropertyTree"])
    ]
)
