// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "PDFMercury",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
    .macCatalyst(.v15),
  ],
  products: [
    .library(
      name: "PDFMercury",
      targets: ["PDFMercury"]
    )
  ],
  targets: [
    .target(
      name: "PDFMercury"
    )
  ]
)
