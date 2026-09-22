import CoreGraphics
import Foundation
import WebKit

@MainActor
final class WebRenderSession {
  private let webView = WKWebView(frame: .zero)
  private var footerWebView: WKWebView?

  func render(
    document: RenderDocument,
    pageFooter: PageFooter?
  ) async throws -> Data {
    try Task.checkCancellation()
    let pageLayout = document.pageLayout
    let contentPageRect = CGRect(origin: .zero, size: pageLayout.contentRect.size)
    webView.frame = contentPageRect
    let navigationObserver = WebViewNavigationObserver()

    try await navigationObserver.load(
      document.html,
      baseURL: document.baseURL,
      in: webView
    )

    let footerRenderer: PageFooterRenderer?
    if let pageFooter {
      let footerView = footerWebView ?? WKWebView(frame: contentPageRect)
      footerWebView = footerView
      footerRenderer = try await PageFooterRenderer(source: webView, webView: footerView, configuration: pageFooter,
        baseURL: document.baseURL, size: contentPageRect.size)
      // A full-page viewport inflates scrollHeight even for an empty document.
      // Measure the remaining flow without counting that artificial blank area.
      webView.frame.size.height = 1
    } else {
      footerRenderer = nil
    }

    let overflowStyle: [String]?
    if footerRenderer != nil {
      overflowStyle = try await webView.evaluateJavaScript("""
        (() => {
          const style = document.documentElement.style;
          const original = [style.getPropertyValue('overflow'), style.getPropertyPriority('overflow')];
          style.setProperty('overflow', 'hidden', 'important');
          return original;
        })()
        """) as? [String]
    } else {
      overflowStyle = nil
    }
    let contentHeight = try await contentHeight(in: webView)
    let pageCount = max(
      1,
      Int(ceil((contentHeight - Self.pageBoundaryTolerance) / contentPageRect.height))
    )
    webView.frame = CGRect(
      origin: .zero,
      size: CGSize(
        width: contentPageRect.width,
        height: CGFloat(pageCount) * contentPageRect.height
      )
    )
    if let overflowStyle, overflowStyle.count == 2 {
      _ = try await webView.callAsyncJavaScript(
        "document.documentElement.style.setProperty('overflow', value, priority);",
        arguments: ["value": overflowStyle[0], "priority": overflowStyle[1]],
        in: nil, contentWorld: .page)
    }

    let pageBreakAvoidanceRanges = try await pageBreakAvoidanceRanges(in: webView)
    let tableContinuations = try await tableContinuations(in: webView)
    var footerHeight: CGFloat = 0
    var pageSlices: [PageSlice] = []
    var expectedPageCount = 1
    var converged = false
    // Counter text can wrap differently as the number of pages changes. Reserve
    // the largest observed height; shrinking it again could oscillate pagination.
    for _ in 0..<12 {
      if let footerRenderer {
        for pageNumber in 1...expectedPageCount {
          footerHeight = max(footerHeight,
            try await footerRenderer.height(pageNumber: pageNumber, pageCount: expectedPageCount))
        }
      }
      let reservedHeight = footerHeight + (pageFooter.map { CGFloat($0.gap) } ?? 0)
      let bodyHeight = contentPageRect.height - reservedHeight
      guard bodyHeight > Self.pageBoundaryTolerance else {
        throw PDFMercuryError.invalidPageFooter("The footer and gap leave no room for page content.")
      }
      pageSlices = try await PDFWorkQueue.perform {
        PDFPagination.pageSlices(contentHeight: contentHeight,
          pageSize: CGSize(width: contentPageRect.width, height: bodyHeight),
          pageBreakAvoidanceRanges: pageBreakAvoidanceRanges, tableContinuations: tableContinuations)
      }
      if footerRenderer == nil || pageSlices.count == expectedPageCount {
        converged = true
        break
      }
      expectedPageCount = pageSlices.count
    }
    guard converged else {
      throw PDFMercuryError.invalidPageFooter("The footer height did not stabilize during pagination.")
    }
    var pages: [RenderedPage] = []
    pages.reserveCapacity(pageSlices.count)
    for (index, pageSlice) in pageSlices.enumerated() {
      try Task.checkCancellation()
      let bodyConfiguration = WKPDFConfiguration()
      bodyConfiguration.rect = pageSlice.bodyRect
      let body = try await webView.pdf(configuration: bodyConfiguration)
      try Task.checkCancellation()

      var repeatedHeader: Data?
      if let headerRect = pageSlice.repeatedHeaderRect {
        let headerConfiguration = WKPDFConfiguration()
        headerConfiguration.rect = headerRect
        repeatedHeader = try await webView.pdf(configuration: headerConfiguration)
      }

      let footer = try await footerRenderer?.render(pageNumber: index + 1,
        pageCount: pageSlices.count, maximumHeight: footerHeight)
      pages.append(
        RenderedPage(
          body: body,
          repeatedHeader: repeatedHeader,
          repeatedHeaderHeight: pageSlice.repeatedHeaderRect?.height ?? 0,
          footer: footer?.0,
          footerHeight: footer?.1 ?? 0
        )
      )
    }

    let renderedPages = pages
    return try await PDFWorkQueue.perform {
      try PDFComposer.combine(renderedPages, pageLayout: pageLayout)
    }
  }

  private static let pageBoundaryTolerance: CGFloat = 0.5

  private func pageBreakAvoidanceRanges(in webView: WKWebView) async throws -> [VerticalRange] {
    let script = """
      (() => {
        const ranges = [];
        const walker = document.createTreeWalker(
          document.body,
          NodeFilter.SHOW_TEXT
        );

        while (walker.nextNode()) {
          const node = walker.currentNode;
          if (!node.textContent || !node.textContent.trim()) continue;

          const range = document.createRange();
          range.selectNodeContents(node);
          for (const rect of range.getClientRects()) {
            if (rect.width > 0 && rect.height > 0) {
              ranges.push([
                rect.top + window.scrollY,
                rect.bottom + window.scrollY
              ]);
            }
          }
        }

        for (const element of document.body.querySelectorAll('*')) {
          const style = getComputedStyle(element);
          if (style.breakInside !== 'avoid' && style.breakInside !== 'avoid-page'
              && style.pageBreakInside !== 'avoid') continue;
          if (style.position === 'absolute' || style.position === 'fixed'
              || style.display === 'inline') continue;
          const rect = element.getBoundingClientRect();
          if (rect.width > 0 && rect.height > 0) {
            ranges.push([
              rect.top + window.scrollY,
              rect.bottom + window.scrollY
            ]);
          }
        }

        for (const table of document.querySelectorAll('table')) {
          const rows = Array.from(table.rows);
          for (const row of rows) {
            const rect = row.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0) continue;
            ranges.push([
              rect.top + window.scrollY,
              rect.bottom + window.scrollY
            ]);
          }

          const header = table.tHead?.getBoundingClientRect();
          const firstBodyRow = Array.from(table.tBodies)
            .flatMap(body => Array.from(body.rows))[0]
            ?.getBoundingClientRect();
          if (header && firstBodyRow && header.height > 0 && firstBodyRow.height > 0) {
            ranges.push([
              header.top + window.scrollY,
              firstBodyRow.bottom + window.scrollY
            ]);
          }
        }

        return ranges;
      })()
      """
    let result = try await webView.evaluateJavaScript(script)
    guard let values = result as? [[NSNumber]] else {
      throw PDFMercuryError.invalidRenderedPDF
    }
    return values.compactMap { value in
      guard value.count == 2 else { return nil }
      return VerticalRange(
        minY: CGFloat(value[0].doubleValue),
        maxY: CGFloat(value[1].doubleValue)
      )
    }
  }

  private func tableContinuations(in webView: WKWebView) async throws
    -> [TableContinuation]
  {
    let script = """
      (() => {
        const continuations = [];

        for (const table of document.querySelectorAll('table')) {
          const header = table.tHead?.getBoundingClientRect();
          if (!header || header.width <= 0 || header.height <= 0) continue;

          const bodyRows = Array.from(table.tBodies)
            .flatMap(body => Array.from(body.rows));
          for (const row of bodyRows) {
            const rect = row.getBoundingClientRect();
            if (rect.width <= 0 || rect.height <= 0) continue;
            continuations.push([
              rect.top + window.scrollY,
              rect.bottom + window.scrollY,
              header.top + window.scrollY,
              header.bottom + window.scrollY
            ]);
          }
        }

        return continuations;
      })()
      """
    let result = try await webView.evaluateJavaScript(script)
    guard let values = result as? [[NSNumber]] else {
      throw PDFMercuryError.invalidRenderedPDF
    }
    return values.compactMap { value in
      guard value.count == 4 else { return nil }
      return TableContinuation(
        rowRange: VerticalRange(
          minY: CGFloat(value[0].doubleValue),
          maxY: CGFloat(value[1].doubleValue)
        ),
        headerRange: VerticalRange(
          minY: CGFloat(value[2].doubleValue),
          maxY: CGFloat(value[3].doubleValue)
        )
      )
    }
  }

  private func contentHeight(in webView: WKWebView) async throws -> CGFloat {
    let script = """
      Math.max(
        document.documentElement.getBoundingClientRect().height,
        document.body ? document.body.getBoundingClientRect().height : 0,
        document.documentElement.scrollHeight,
        document.body ? document.body.scrollHeight : 0
      )
      """
    let result = try await webView.evaluateJavaScript(script)
    guard let number = result as? NSNumber else {
      throw PDFMercuryError.invalidRenderedPDF
    }
    return CGFloat(number.doubleValue)
  }

}
