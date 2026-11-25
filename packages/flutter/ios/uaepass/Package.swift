// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "uaepass",
  platforms: [.iOS(.v15)],
  products: [.library(name: "uaepass", targets: ["uaepass"])],
  dependencies: [
    .package(name: "FlutterFramework", path: "../FlutterFramework"),
    .package(name: "webview_flutter_wkwebview", path: "../webview_flutter_wkwebview")
  ],
  targets: [
    .target(
      name: "uaepass",
      dependencies: [
        .product(name: "FlutterFramework", package: "FlutterFramework"),
        .product(name: "webview-flutter-wkwebview", package: "webview_flutter_wkwebview")
      ]
    ),
  ]
)
