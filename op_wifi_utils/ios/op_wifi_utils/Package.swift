// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "op_wifi_utils",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "op-wifi-utils", targets: ["op_wifi_utils"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "op_wifi_utils",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ],    
)