import Foundation
import PDFKit
import PDFMercury
import Testing

@Suite("Content-aware pagination")
@MainActor
struct PaginationTests {
  @Test("Keeps an invoice summary together at a page boundary", arguments: [
    "break-inside: avoid", "break-inside: avoid-page", "page-break-inside: avoid",
  ])
  func keepsSummaryTogether(rule: String) async throws {
    let html = """
      <html><body>
        <div style="height: 680px">INVOICE CONTENT</div>
        <section style="\(rule)">
          <div style="height: 70px">SUBTOTAL MARKER</div>
          <div style="height: 70px">TOTAL MARKER</div>
        </section>
      </body></html>
      """
    let pdf = try await RenderEngine().render(
      html: .string(html), stylesheets: [.string(Self.stylesheet)]
    )
    let document = try #require(PDFDocument(data: pdf))
    #expect(document.pageCount == 2)
    #expect(document.page(at: 0)?.string?.contains("INVOICE CONTENT") == true)
    #expect(document.page(at: 0)?.string?.contains("SUBTOTAL MARKER") == false)
    #expect(document.page(at: 1)?.string?.contains("SUBTOTAL MARKER") == true)
    #expect(document.page(at: 1)?.string?.contains("TOTAL MARKER") == true)
  }

  @Test("Splits overheight content without losing or duplicating text", arguments: [false, true])
  func splitsOverheightContent(isTable: Bool) async throws {
    let markers = (1...100).map { String(format: "LINE%03dEND", $0) }
    let lines = markers.map { "<div>\($0)</div>" }.joined()
    let content = isTable
      ? "<table><thead><tr><th>POSITION</th></tr></thead><tbody><tr><td>\(lines)</td></tr></tbody></table>"
      : "<section style=\"break-inside: avoid\">\(lines)</section>"
    let pdf = try await RenderEngine().render(
      html: .string("<html><body>\(content)</body></html>"),
      stylesheets: [.string(Self.stylesheet + """
        body { font-size: 18px; line-height: 23px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 0; text-align: left; }
        """)]
    )
    let document = try #require(PDFDocument(data: pdf))
    #expect(document.pageCount >= 3)
    #expect(document.pageCount <= 5)
    let pageTexts = (0..<document.pageCount).map {
      (document.page(at: $0)?.string ?? "").filter { !$0.isWhitespace }
    }
    for marker in markers {
      let occurrences = pageTexts.reduce(0) { $0 + $1.components(separatedBy: marker).count - 1 }
      #expect(occurrences == 1, "Expected exactly one intact copy of \(marker)")
      for selection in document.findString(marker, withOptions: []) {
        let page = try #require(selection.pages.first)
        let bounds = selection.bounds(for: page)
        #expect(bounds.minY >= 47.5, "Clipped bottom of \(marker)")
        #expect(bounds.maxY <= page.bounds(for: .mediaBox).height - 47.5,
          "Clipped top of \(marker)")
      }
    }
    if isTable {
      for pageText in pageTexts where pageText.contains("LINE") {
        #expect(pageText.components(separatedBy: "POSITION").count - 1 == 1)
      }
    }
  }

  private static let stylesheet = """
    @page { size: A4; margin: 48pt; }
    html, body { margin: 0; padding: 0; font-family: Helvetica; font-size: 12px; }
    """
}
