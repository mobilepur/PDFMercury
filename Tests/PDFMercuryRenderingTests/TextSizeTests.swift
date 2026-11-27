import Foundation
import PDFKit
import PDFMercury
import Testing

#if canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
#else
import AppKit
private typealias PlatformFont = NSFont
#endif

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
    // 15 CSS pixels are 11.25 pt.
    #expect(abs(first.minY - second.minY - 11.25) < 0.5)
  }

  @Test("Maps one CSS pixel to 0.75 pt and page margins to their physical size")
  func cssUnitsKeepTheirPhysicalSize() async throws {
    let html = "<html><body><p>MARKER</p></body></html>"
    let pdf = try await RenderEngine().render(
      html: .string(html),
      stylesheets: [.string("@page { size: A4; margin: 20mm 25mm; } body { margin: 0; font: 16px/16px Helvetica; }")]
    )
    let document = try #require(PDFDocument(data: pdf))
    let page = try #require(document.page(at: 0))
    let mediaBox = page.bounds(for: .mediaBox)
    #expect(abs(mediaBox.width - 595.28) < 0.5)
    #expect(abs(mediaBox.height - 841.89) < 0.5)
    let attributes = try #require(page.attributedString)
    let font = try #require(attributes.attribute(.font, at: 0, effectiveRange: nil) as? PlatformFont)
    #expect(abs(font.pointSize - 12) < 0.01)
    let marker = try #require(document.findString("MARKER", withOptions: []).first).bounds(for: page)
    let millimeter = 72 / 25.4
    #expect(abs(marker.minX - 25 * millimeter) < 1)
    #expect(abs(mediaBox.height - marker.maxY - 20 * millimeter) < 2)
  }
}
