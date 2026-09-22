import Foundation
import PDFKit
import PDFMercury
import Testing

@Suite("Running page footers")
@MainActor
struct PageFooterTests {
  @Test("Repeats bottom-aligned footer and counters without losing body text", arguments: [1, 80])
  func repeatsFooter(lineCount: Int) async throws {
    let markers = (1...lineCount).map { String(format: "BODY%03dEND", $0) }
    let rows = markers.map { "<tr><td>\($0)</td></tr>" }.joined()
    let html = """
      <html><body class="invoice">
      <table><thead><tr><th>TABLE HEADER</th></tr></thead><tbody>\(rows)</tbody></table>
      <footer id="running">FOOTER MARKER <span data-pdf-page-number></span> / <span data-pdf-page-count></span></footer>
      </body></html>
      """
    let data = try await RenderEngine().render(html: .string(html),
      stylesheets: [.string(Self.css)], pageFooter: PageFooter(elementID: "running"))
    let document = try #require(PDFDocument(data: data))
    #expect(lineCount == 1 ? document.pageCount == 1 : document.pageCount >= 3)
    let allText = document.string ?? ""
    for marker in markers {
      #expect(allText.components(separatedBy: marker).count - 1 == 1)
    }
    var baseline: CGFloat?
    for index in 0..<document.pageCount {
      let page = try #require(document.page(at: index))
      let text = page.string ?? ""
      #expect(text.components(separatedBy: "FOOTER MARKER").count - 1 == 1)
      #expect(text.contains("FOOTER MARKER \(index + 1) / \(document.pageCount)"))
      #expect(text.components(separatedBy: "TABLE HEADER").count - 1 == 1)
      let footer = try #require(document.findString("FOOTER MARKER", withOptions: [])
        .first { $0.pages.contains(page) })
      let bounds = footer.bounds(for: page)
      #expect(bounds.minY >= 47)
      #expect(bounds.maxY < 100)
      if let baseline { #expect(abs(baseline - bounds.minY) < 0.5) }
      baseline = bounds.minY
      for marker in markers {
        for selection in document.findString(marker, withOptions: []) where selection.pages.contains(page) {
          #expect(selection.bounds(for: page).minY > bounds.maxY + 10)
        }
      }
    }
  }

  @Test("Nil preserves one normal-flow footer")
  func noFooterOption() async throws {
    let rows = (1...80).map { "<div style='height:24px'>ROW \($0)</div>" }.joined()
    let data = try await RenderEngine().render(html: .string("<html><body>\(rows)<footer>END FOOTER</footer></body></html>"),
      stylesheets: [.string(Self.css)])
    let document = try #require(PDFDocument(data: data))
    #expect(document.pageCount >= 3)
    #expect((document.string ?? "").components(separatedBy: "END FOOTER").count - 1 == 1)
    #expect(document.page(at: document.pageCount - 1)?.string?.contains("END FOOTER") == true)
  }

  @Test("Remeasures wrapping two-digit page counters before reserving space")
  func wrappingCounters() async throws {
    let markers = (1...350).map { String(format: "WRAP%03dEND", $0) }
    let rows = markers.map { "<div style='height:24px'>\($0)</div>" }.joined()
    let data = try await RenderEngine().render(
      html: .string("""
        <html><body>\(rows)<footer id="running">WRAP FOOTER
        <div style="width:9px; font:16px/20px monospace; overflow-wrap:anywhere"><span data-pdf-page-number></span><span data-pdf-page-count></span></div>
        </footer></body></html>
        """), stylesheets: [.string(Self.css)], pageFooter: PageFooter(elementID: "running"))
    let document = try #require(PDFDocument(data: data))
    #expect(document.pageCount >= 10)
    let text = document.string ?? ""
    for marker in markers { #expect(text.components(separatedBy: marker).count - 1 == 1) }
    let footers = document.findString("WRAP FOOTER", withOptions: [])
    #expect(footers.count == document.pageCount)
    for index in 0..<document.pageCount {
      let page = try #require(document.page(at: index))
      let footer = try #require(footers.first { $0.pages.contains(page) })
      let footerBounds = footer.bounds(for: page)
      #expect(footerBounds.minY >= 47)
      let pageText = page.string ?? ""
      let counter = String(pageText.components(separatedBy: "WRAP FOOTER").last ?? "")
        .filter { !$0.isWhitespace }
      #expect(counter == "\(index + 1)\(document.pageCount)")
      for marker in markers where pageText.contains(marker) {
        let selection = try #require(document.findString(marker, withOptions: []).first)
        #expect(selection.bounds(for: page).minY > footerBounds.maxY + 10)
      }
    }
  }

  @Test("Escaped IDs and empty body work")
  func escapedID() async throws {
    let data = try await RenderEngine().render(
      html: .string("<html><body><footer id=\"quote'&quot;\\id\">ONLY FOOTER</footer></body></html>"),
      stylesheets: [.string(Self.css)], pageFooter: PageFooter(elementID: "quote'\"\\id"))
    let document = try #require(PDFDocument(data: data))
    #expect(document.pageCount == 1)
    #expect(document.string?.contains("ONLY FOOTER") == true)
  }

  @Test("Preserves horizontal body insets without introducing a scrollbar gutter")
  func horizontalInsets() async throws {
    let data = try await RenderEngine().render(
      html: .string("<html><body><div>BODY ALIGNMENT</div><footer id='running'>FOOTER ALIGNMENT</footer></body></html>"),
      stylesheets: [.string(Self.css + "@page { margin: 48px; } body { padding: 22px; border-left: 18px solid black; }")],
      pageFooter: PageFooter(elementID: "running"))
    let document = try #require(PDFDocument(data: data))
    let page = try #require(document.page(at: 0))
    let body = try #require(document.findString("BODY ALIGNMENT", withOptions: []).first)
    let footer = try #require(document.findString("FOOTER ALIGNMENT", withOptions: []).first)
    #expect(abs(body.bounds(for: page).minX - footer.bounds(for: page).minX) < 0.5)
    #expect(abs(footer.bounds(for: page).minX - 88) < 0.5)
  }

  @Test("Fractional page widths fit the footer on mobile WebKit")
  func fractionalPageWidth() async throws {
    let data = try await RenderEngine().render(
      html: .string("<html><body>BODY<footer id='running'>FRACTIONAL FOOTER <span data-pdf-page-number></span></footer></body></html>"),
      stylesheets: [.string(Self.css + "@page { margin: 18mm 17mm 16mm; } footer { width: 100%; box-sizing: border-box; }")],
      pageFooter: PageFooter(elementID: "running"))
    let document = try #require(PDFDocument(data: data))
    #expect(document.pageCount == 1)
    #expect(document.string?.contains("FRACTIONAL FOOTER 1") == true)
  }

  @Test("Invalid footer requests fail explicitly", arguments: [
    "", "<footer id='running' style='height:1000px'>TALL</footer>",
    "<div><footer id='running'>NESTED</footer></div>",
    "<footer id='running' style='display:none'>HIDDEN</footer>",
    "<footer id='running'>ONE</footer><footer id='running'>TWO</footer>",
    "<footer id='running' style='position:fixed'>FIXED</footer>",
  ])
  func invalidFooter(markup: String) async throws {
    await #expect { try await RenderEngine().render(html: .string("<html><body>\(markup)</body></html>"),
      stylesheets: [.string(Self.css)], pageFooter: PageFooter(elementID: "running")) } throws: { error in
        guard case PDFMercuryError.invalidPageFooter = error else { return false }
        return true
      }
  }

  @Test("Invalid gaps fail explicitly", arguments: [-1.0, Double.infinity, Double.nan])
  func invalidGap(gap: Double) async throws {
    await #expect { try await RenderEngine().render(html: .string("<footer id='running'>FOOTER</footer>"),
      pageFooter: PageFooter(elementID: "running", gap: gap)) } throws: { error in
        guard case PDFMercuryError.invalidPageFooter = error else { return false }
        return true
      }
  }

  private static let css = """
    @page { size: A4; margin: 48pt; }
    html, body { margin: 0; padding: 0; font-family: Helvetica; font-size: 12px; }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 4px 0; line-height: 18px; text-align: left; }
    body.invoice > footer { padding-top: 8px; border-top: 1px solid black; }
    """
}
