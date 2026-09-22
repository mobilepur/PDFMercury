import Foundation
import PDFKit
import PDFMercury
import Testing

@Suite("Render session isolation", .serialized)
@MainActor
struct RenderConcurrencyTests {
  @Test("A cancelled request does not start rendering")
  func cancelledRequest() async throws {
    let task = Task { @MainActor in
      try await RenderEngine().render(html: .string("<p>Cancelled document</p>"))
    }
    task.cancel()
    do {
      _ = try await task.value
      Issue.record("Rendering returned a PDF for an already cancelled request")
    } catch is CancellationError {
      // Expected: cancellation is propagated to the caller.
    }
  }

  @Test("Concurrent requests keep their body and footer separate")
  func concurrentDocuments() async throws {
    let first = Task { @MainActor in
      try await render(body: "FIRST DOCUMENT", footer: "FIRST FOOTER", landscape: false)
    }
    let second = Task { @MainActor in
      try await render(body: "SECOND DOCUMENT", footer: "SECOND FOOTER", landscape: true)
    }
    let firstPDF = try #require(PDFDocument(data: try await first.value))
    let secondPDF = try #require(PDFDocument(data: try await second.value))
    #expect(firstPDF.string?.contains("FIRST DOCUMENT") == true)
    #expect(firstPDF.string?.contains("FIRST FOOTER") == true)
    #expect(firstPDF.string?.contains("SECOND") == false)
    #expect(secondPDF.string?.contains("SECOND DOCUMENT") == true)
    #expect(secondPDF.string?.contains("SECOND FOOTER") == true)
    #expect(secondPDF.string?.contains("FIRST") == false)
    #expect(firstPDF.page(at: 0)!.bounds(for: .mediaBox).width < 600)
    #expect(secondPDF.page(at: 0)!.bounds(for: .mediaBox).width > 800)
  }

  @Test("A following document resets the footer, viewport and styles")
  func followingDocument() async throws {
    _ = try await render(body: "PREVIOUS BODY", footer: "PREVIOUS FOOTER", landscape: true)
    let data = try await RenderEngine().render(
      html: .string("<html><body><p>CURRENT BODY</p></body></html>"),
      stylesheets: [.string("@page {size: A4; margin: 30pt;} body {font-size: 16px;}")]
    )
    let document = try #require(PDFDocument(data: data))
    #expect(document.pageCount == 1)
    #expect(document.string?.contains("CURRENT BODY") == true)
    #expect(document.string?.contains("PREVIOUS") == false)
    #expect(document.page(at: 0)!.bounds(for: .mediaBox).width < 600)
  }

  @Test("A failed footer render does not poison the next request")
  func recoveryAfterFailure() async throws {
    do {
      _ = try await RenderEngine().render(
        html: .string("<html><body>INVALID FOOTER</body></html>"),
        pageFooter: .init(elementID: "missing")
      )
      Issue.record("Expected invalid footer to fail")
    } catch PDFMercuryError.invalidPageFooter {
      // A subsequent request must still work after failure.
    }
    let data = try await render(body: "RECOVERED BODY", footer: "RECOVERED FOOTER", landscape: false)
    let document = try #require(PDFDocument(data: data))
    #expect(document.string?.contains("RECOVERED BODY") == true)
    #expect(document.string?.contains("RECOVERED FOOTER") == true)
    #expect(document.string?.contains("INVALID") == false)
  }

  private func render(body: String, footer: String, landscape: Bool) async throws -> Data {
    try await RenderEngine().render(
      html: .string("<html><body><main>\(body)</main><footer id='footer'>\(footer)</footer></body></html>"),
      stylesheets: [.string("@page {size: A4 \(landscape ? "landscape" : "portrait"); margin: 30pt;} body {font-size: 16px;}")],
      pageFooter: .init(elementID: "footer")
    )
  }
}
