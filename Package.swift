// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "whooshing.toolbox-file-storage",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
        .watchOS(.v7),
        .tvOS(.v14),
    ],
    products: [
        .library( name: "FileStorage", targets: ["FileStorage"] )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.10.0"),
//        .package(url: "https://github.com/SJJC-Team/whooshing.toolbox-basic.git", .upToNextMajor(from: "1.3.9")),
        .package(path: "/Users/clwang/GitHub/whooshing.toolbox-basic"),
//        .package(url: "https://github.com/SJJC-Team/whooshing.toolbox-pgsql.git", .upToNextMajor(from: "1.0.0")),
        .package(path: "/Users/clwang/GitHub/whooshing.toolbox-pgsql")
    ],
    targets: [
        .target(
            name: "FileStorage",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "PgSQL", package: "whooshing.toolbox-pgsql"),
                .product(name: "ErrorHandle", package: "whooshing.toolbox-basic"),
                .product(name: "DataConvertable", package: "whooshing.toolbox-basic"),
                .product(name: "Cryptos", package: "whooshing.toolbox-basic"),
                .product(name: "_NIOFileSystem", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "toolbox-file-storage-Tests",
            dependencies: [
                .target(name: "FileStorage"),
            ]
        ),
    ]
)
