# PDFMercury

PDFMercury is a Swift package that renders HTML and CSS into paginated, vector-based PDF documents with WebKit.

## Requirements

- Swift 6.0+
- iOS 15+
- macOS 12+
- Mac Catalyst 15+

## Installation

Add the package in Xcode or declare it in `Package.swift`:

```swift
.package(
  url: "https://github.com/mobilepur/PDFMercury.git",
  from: "0.1.0"
)
```

Then add the `PDFMercury` library product to your target.

## Usage

```swift
import Foundation
import PDFMercury

@MainActor
func createInvoicePDF() async throws -> Data {
  let documents = FileManager.default.urls(
    for: .documentDirectory,
    in: .userDomainMask
  )[0]

  return try await RenderEngine().render(
    html: .string(
      "<h1>Invoice</h1><img src=\"company-logo.svg\">",
      baseURL: documents
    ),
    stylesheets: [
      .file(documents.appendingPathComponent("invoice.css"))
    ]
  )
}
```

## More

- [Documentation](Doc/documentation.md)
- [Release notes](Doc/release_notes.md)
- [Development log](Doc/log.md)
- [Visual testing](Tests/VISUAL_REPORTS.md)

PDFMercury is available under the [MIT License](LICENSE).
