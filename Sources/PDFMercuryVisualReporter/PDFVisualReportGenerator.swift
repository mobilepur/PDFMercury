import CoreGraphics
import CoreText
import Foundation

public struct PDFVisualReportGenerator: Sendable {
  public init() {}

  public func generate(from inputURLs: [URL], to outputURL: URL) throws {
    let reportName = outputURL.deletingPathExtension().lastPathComponent
    let documents = try loadDocuments(from: inputURLs)
    let pageCount = documents.reduce(0) { $0 + $1.pageCount }
    guard pageCount > 0 else {
      throw PDFVisualReportError.noPages
    }

    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var reportBounds = Layout.reportBounds
    guard
      let consumer = CGDataConsumer(url: outputURL as CFURL),
      let context = CGContext(
        consumer: consumer,
        mediaBox: &reportBounds,
        [
          kCGPDFContextTitle: reportName,
          kCGPDFContextCreator: "PDFMercury",
        ] as CFDictionary
      )
    else {
      throw PDFVisualReportError.cannotCreateReport(outputURL)
    }

    let reportPageCount = Int(ceil(Double(pageCount) / Double(Layout.previewsPerPage)))
    var pageOffset = 0

    for reportPageIndex in 0..<reportPageCount {
      context.beginPDFPage(nil)
      drawReportBackground(in: context)
      drawHeader(
        reportName: reportName,
        page: reportPageIndex + 1,
        pageCount: reportPageCount,
        in: context
      )

      for slot in 0..<Layout.previewsPerPage where pageOffset < pageCount {
        let source = sourcePage(at: pageOffset, in: documents)
        draw(source, in: cellRect(for: slot), context: context)
        pageOffset += 1
      }

      context.endPDFPage()
    }

    context.closePDF()

    guard CGPDFDocument(outputURL as CFURL)?.numberOfPages == reportPageCount else {
      throw PDFVisualReportError.invalidGeneratedReport(outputURL)
    }
  }

  private func loadDocuments(from inputURLs: [URL]) throws -> [SourceDocument] {
    try inputURLs.map { url in
      guard url.isFileURL, let document = CGPDFDocument(url as CFURL) else {
        throw PDFVisualReportError.invalidPDF(url)
      }
      guard document.numberOfPages > 0 else {
        throw PDFVisualReportError.emptyPDF(url)
      }
      return SourceDocument(url: url, document: document)
    }
  }

  private func sourcePage(at offset: Int, in documents: [SourceDocument]) -> SourcePage {
    var remainingOffset = offset

    for document in documents {
      if remainingOffset < document.pageCount {
        let pageNumber = remainingOffset + 1
        return SourcePage(
          label: "\(document.url.lastPathComponent) - \(pageNumber)/\(document.pageCount)",
          page: document.document.page(at: pageNumber)!
        )
      }
      remainingOffset -= document.pageCount
    }

    preconditionFailure("The page offset must refer to a loaded source page")
  }

  private func drawReportBackground(in context: CGContext) {
    context.setFillColor(CGColor(gray: 0.94, alpha: 1))
    context.fill(Layout.reportBounds)
  }

  private func drawHeader(
    reportName: String,
    page: Int,
    pageCount: Int,
    in context: CGContext
  ) {
    drawText(
      reportName,
      at: CGPoint(x: Layout.margin, y: Layout.reportBounds.height - Layout.margin - 12),
      maximumWidth: 300,
      fontSize: 13,
      color: CGColor(gray: 0.12, alpha: 1),
      in: context
    )
    drawText(
      "Report page \(page)/\(pageCount)",
      at: CGPoint(
        x: Layout.reportBounds.width - Layout.margin - 110,
        y: Layout.reportBounds.height - Layout.margin - 12),
      maximumWidth: 110,
      fontSize: 9,
      color: CGColor(gray: 0.35, alpha: 1),
      in: context
    )
  }

  func cellRect(for slot: Int) -> CGRect {
    let column = slot % Layout.columns
    let row = slot / Layout.columns
    let availableWidth =
      Layout.reportBounds.width
      - (2 * Layout.margin)
      - (CGFloat(Layout.columns - 1) * Layout.gap)
    let availableHeight =
      Layout.reportBounds.height
      - (2 * Layout.margin)
      - Layout.headerHeight
      - (CGFloat(Layout.rows - 1) * Layout.gap)
    let cellSize = min(
      availableWidth / CGFloat(Layout.columns),
      availableHeight / CGFloat(Layout.rows)
    )
    let gridHeight = CGFloat(Layout.rows) * cellSize + CGFloat(Layout.rows - 1) * Layout.gap
    let gridOriginY = Layout.margin + (availableHeight + Layout.gap - gridHeight) / 2
    let x = Layout.margin + CGFloat(column) * (cellSize + Layout.gap)
    let y = gridOriginY + CGFloat(Layout.rows - row - 1) * (cellSize + Layout.gap)
    return CGRect(x: x, y: y, width: cellSize, height: cellSize)
  }

  private func draw(_ source: SourcePage, in cellRect: CGRect, context: CGContext) {
    context.saveGState()
    context.setFillColor(CGColor(gray: 0.88, alpha: 1))
    context.setStrokeColor(CGColor(gray: 0.72, alpha: 1))
    context.setLineWidth(0.5)
    context.fill(cellRect)
    context.stroke(cellRect)

    let labelOrigin = CGPoint(
      x: cellRect.minX + Layout.cellPadding,
      y: cellRect.maxY - Layout.labelHeight
    )
    drawText(
      source.label,
      at: labelOrigin,
      maximumWidth: cellRect.width - (2 * Layout.cellPadding),
      fontSize: 7.5,
      color: CGColor(gray: 0.2, alpha: 1),
      in: context
    )

    let previewRect = CGRect(
      x: cellRect.minX + Layout.cellPadding,
      y: cellRect.minY + Layout.cellPadding,
      width: cellRect.width - (2 * Layout.cellPadding),
      height: cellRect.height - Layout.labelHeight - (2 * Layout.cellPadding)
    )
    let pageRect = fittedPageRect(
      pageBounds: source.page.getBoxRect(.cropBox),
      rotationAngle: source.page.rotationAngle,
      in: previewRect
    )
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.setStrokeColor(CGColor(gray: 0.58, alpha: 1))
    context.fill(pageRect)
    context.stroke(pageRect)
    context.clip(to: pageRect)
    context.concatenate(
      source.page.getDrawingTransform(
        .cropBox,
        rect: pageRect,
        rotate: 0,
        preserveAspectRatio: true
      )
    )
    context.drawPDFPage(source.page)
    context.restoreGState()
  }

  func fittedPageRect(
    pageBounds: CGRect,
    rotationAngle: Int32,
    in container: CGRect
  ) -> CGRect {
    let normalizedRotation = ((rotationAngle % 360) + 360) % 360
    let isQuarterTurn = normalizedRotation == 90 || normalizedRotation == 270
    let effectiveSize =
      isQuarterTurn
      ? CGSize(width: pageBounds.height, height: pageBounds.width)
      : pageBounds.size
    guard effectiveSize.width > 0, effectiveSize.height > 0 else {
      return container
    }

    let scale = min(
      container.width / effectiveSize.width,
      container.height / effectiveSize.height
    )
    let fittedSize = CGSize(
      width: effectiveSize.width * scale,
      height: effectiveSize.height * scale
    )
    return CGRect(
      x: container.midX - fittedSize.width / 2,
      y: container.midY - fittedSize.height / 2,
      width: fittedSize.width,
      height: fittedSize.height
    )
  }

  private func drawText(
    _ text: String,
    at point: CGPoint,
    maximumWidth: CGFloat,
    fontSize: CGFloat,
    color: CGColor,
    in context: CGContext
  ) {
    let attributes: [CFString: Any] = [
      kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
      kCTForegroundColorAttributeName: color,
    ]
    let attributedText = CFAttributedStringCreate(
      nil, text as CFString, attributes as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributedText)
    let ellipsisText = CFAttributedStringCreate(nil, "..." as CFString, attributes as CFDictionary)!
    let ellipsis = CTLineCreateWithAttributedString(ellipsisText)
    let visibleLine = CTLineCreateTruncatedLine(line, Double(maximumWidth), .end, ellipsis) ?? line

    context.textPosition = point
    CTLineDraw(visibleLine, context)
  }
}

public enum PDFVisualReportError: Error, Equatable {
  case cannotCreateReport(URL)
  case emptyPDF(URL)
  case invalidGeneratedReport(URL)
  case invalidPDF(URL)
  case noPages
}

extension PDFVisualReportError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .cannotCreateReport(let url):
      "Could not create the PDF report at \(url.path)."
    case .emptyPDF(let url):
      "The PDF at \(url.path) contains no pages."
    case .invalidGeneratedReport(let url):
      "The generated report at \(url.path) is not a valid PDF."
    case .invalidPDF(let url):
      "The file at \(url.path) is not a readable PDF."
    case .noPages:
      "At least one PDF page is required to generate a report."
    }
  }
}

private struct SourceDocument {
  let url: URL
  let document: CGPDFDocument

  var pageCount: Int { document.numberOfPages }
}

private struct SourcePage {
  let label: String
  let page: CGPDFPage
}

private enum Layout {
  static let columns = 4
  static let rows = 2
  static let previewsPerPage = columns * rows
  static let reportBounds = CGRect(x: 0, y: 0, width: 841.89, height: 595.28)
  static let margin: CGFloat = 20
  static let gap: CGFloat = 10
  static let headerHeight: CGFloat = 24
  static let cellPadding: CGFloat = 5
  static let labelHeight: CGFloat = 15
}
