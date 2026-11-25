import Foundation
import PDFKit
import PDFMercury
import Testing

@Suite("Text size")
@MainActor
struct TextSizeTests {
  /// Mobile WebKit enlarges the lines of text on its own. A PDF keeps the sizes of its
  /// stylesheet, so a document paginates on iOS as it does on the Mac.
  @Test("Lays out lines at the height of the stylesheet", arguments: [false, true])
  func linesKeepTheirHeight(hasPageFooter: Bool) async throws {
    let prose = String(repeating: "Consulting and development of the invoice layout. ", count: 12)
    let footer = hasPageFooter ? #"<footer id="footer">FOOTER</footer>"# : ""
    let html = """
      <html><body><p>\(prose)</p><p>FIRSTMARKER<br>SECONDMARKER</p>\(footer)</body></html>
      """
    let pdf = try await RenderEngine().render(
      html: .string(html),
      stylesheets: [.string("@page { size: A4; margin: 40px; } body { margin: 0; font: 10px Helvetica; line-height: 15px; }")],
      pageFooter: hasPageFooter ? .init(elementID: "footer") : nil
    )
    let document = try #require(PDFDocument(data: pdf))
    let page = try #require(document.page(at: 0))
    let first = try #require(document.findString("FIRSTMARKER", withOptions: []).first).bounds(for: page)
    let second = try #require(document.findString("SECONDMARKER", withOptions: []).first).bounds(for: page)
    #expect(abs(first.minY - second.minY - 15) < 0.5)
  }
}
