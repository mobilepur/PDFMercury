// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "pdf-mercury",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
    .macCatalyst(.v15),
  ],
  products: [
    .library(
      name: "PDFMercury",
      targets: ["PDFMercury"]
    ),
    .executable(
      name: "pdfmercury-visual-report",
      targets: ["PDFMercuryVisualReportCLI"]
    ),
  ],
  targets: [
    .target(
      name: "PDFMercury"
    ),
    .target(
      name: "PDFMercuryVisualReporter"
    ),
    .executableTarget(
      name: "PDFMercuryVisualReportCLI",
      dependencies: ["PDFMercuryVisualReporter"]
    ),
    .testTarget(
      name: "PDFMercuryVisualReporterTests",
      dependencies: ["PDFMercuryVisualReporter"]
    ),
    .testTarget(
      name: "PDFMercuryRenderingTests",
      dependencies: ["PDFMercury"],
      resources: [
        .copy("Fixtures")
      ]
    ),
  ]
)
