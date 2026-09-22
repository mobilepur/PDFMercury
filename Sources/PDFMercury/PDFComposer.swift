import CoreGraphics
import Foundation

enum PDFComposer {
  static func combine(_ pages: [RenderedPage], pageLayout: PageLayout) throws -> Data {
    let output = NSMutableData()
    guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
      throw PDFMercuryError.couldNotCreatePDF
    }
    var mediaBox = pageLayout.pageRect
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
      throw PDFMercuryError.couldNotCreatePDF
    }

    for page in pages {
      context.beginPDFPage(nil)
      if let repeatedHeader = page.repeatedHeader {
        try draw(
          repeatedHeader,
          in: context,
          pageLayout: pageLayout,
          topInset: 0
        )
      }
      try draw(
        page.body,
        in: context,
        pageLayout: pageLayout,
        topInset: page.repeatedHeaderHeight
      )
      if let footer = page.footer {
        try draw(footer, in: context, pageLayout: pageLayout,
          topInset: pageLayout.contentRect.height - page.footerHeight)
      }
      context.endPDFPage()
    }

    context.closePDF()
    return output as Data
  }

  private static func draw(
    _ data: Data,
    in context: CGContext,
    pageLayout: PageLayout,
    topInset: CGFloat
  ) throws {
    guard
      let provider = CGDataProvider(data: data as CFData),
      let document = CGPDFDocument(provider),
      let page = document.page(at: 1)
    else {
      throw PDFMercuryError.invalidRenderedPDF
    }

    context.saveGState()
    let renderedPageRect = page.getBoxRect(.mediaBox)
    context.clip(to: pageLayout.contentRect)
    context.translateBy(
      x: pageLayout.contentRect.minX - renderedPageRect.minX,
      y: pageLayout.contentRect.maxY - topInset - renderedPageRect.maxY
    )
    context.drawPDFPage(page)
    context.restoreGState()
  }
}
