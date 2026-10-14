// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tray",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Tray",
            path: "Sources",
            exclude: ["App/Info.plist"], // copied into the bundle by Scripts/build-app.sh
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "TrayTests",
            dependencies: ["Tray"],
            path: "Tests"
        )
    ]
)
