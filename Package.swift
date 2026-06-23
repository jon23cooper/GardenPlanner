// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GardenPlanner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GardenPlanner",
            path: "Sources/GardenPlanner",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/GardenPlanner/Info.plist"
                ])
            ]
        )
    ]
)
