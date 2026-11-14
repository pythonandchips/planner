// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PlannerDesk",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PlannerDesk", targets: ["PlannerDesk"]),
    ],
    targets: [
        // Everything that does not need a window: plan discovery, the ACP
        // client, and the observable session model. Tested with swift-testing.
        .target(name: "PlannerCore"),
        // The SwiftUI app.
        .executableTarget(name: "PlannerDesk", dependencies: ["PlannerCore"]),
        .testTarget(
            name: "PlannerCoreTests",
            dependencies: ["PlannerCore"],
            // The Command Line Tools ship _Testing_Foundation.framework without
            // its Modules directory, so `import Testing` + `import Foundation`
            // fails with "no such module '_Testing_Foundation'". Turning the
            // cross-import overlay off is what made the tests build here.
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-disable-cross-import-overlays"])]
        ),
    ]
)
