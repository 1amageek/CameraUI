// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CameraUI",
    platforms: [.iOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "CameraUI",
            targets: ["CameraUI"]),
    ],
    dependencies: [
//        .package(name: "Camera-SwiftUI", url: "git@github.com:rorodriguez116/Camera-SwiftUI.git", .upToNextMajor(from: "0.0.5"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "CameraUI",
            dependencies: [
//                "Camera-SwiftUI"
            ]),
        .testTarget(
            name: "CameraUITests",
            dependencies: [
                "CameraUI",
//                "Camera-SwiftUI"
            ]),
    ]
)
