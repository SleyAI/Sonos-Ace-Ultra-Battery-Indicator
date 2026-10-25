// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SonosAceBattery",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SonosAceBattery",
            path: "Sources/SonosAceBattery",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
