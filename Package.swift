// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CameraUI",
    platforms: [.iOS(.v16)],
    products: [
        .library(
            name: "CameraUI",
            targets: ["CameraUI"]),
    ],
    dependencies: [

    ],
    targets: [
        .target(
            name: "CameraUI",
            dependencies: []),
        .testTarget(
            name: "CameraUITests",
            dependencies: [
                "CameraUI"
            ]),
    ]
)
