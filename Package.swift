// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "whooshing.toolbox-file-storage",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
        .watchOS(.v6),
        .tvOS(.v14),
    ],
    products: [
        .library( name: "FileStorage", targets: ["FileStorage"] )
    ],
    dependencies: [
        .package(url: "https://github.com/whooshing-workshop/whooshing.toolbox-basic.git", from: "1.5.4"),
        .package(url: "https://github.com/whooshing-workshop/whooshing.toolbox-pgsql.git", from: "1.0.8"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "4.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.9.1")
    ],
    targets: [
        .target(
            name: "FileStorage",
            dependencies: [
                .product(name: "PgSQL", package: "whooshing.toolbox-pgsql"),
                .product(name: "ErrorHandle", package: "whooshing.toolbox-basic"),
                .product(name: "NIOAdvanced", package: "whooshing.toolbox-basic"),
                .product(name: "DataConvertable", package: "whooshing.toolbox-basic"),
                .product(name: "Cryptos", package: "whooshing.toolbox-basic"),
                .product(name: "LoggingAdvanced", package: "whooshing.toolbox-basic"),
                .product(name: "_NIOFileSystem", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log")
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
