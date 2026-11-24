// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "uaepass",
  platforms: [.iOS(.v15)],
  products: [.library(name: "uaepass", targets: ["uaepass"])],
  dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
  targets: [
    .target(
      name: "uaepass",
      dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")]
    ),
  ]
)
