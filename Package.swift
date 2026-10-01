// swift-tools-version: 6.2
// The macOS app. The Linux frontend is built by Meson instead.
import PackageDescription

let package = Package(
    name: "TheGiver",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "TheGiver",
            path: "macos/Sources/TheGiver"
        ),
    ],
    swiftLanguageModes: [.v5]
)
