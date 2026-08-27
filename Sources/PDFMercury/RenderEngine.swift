import CoreGraphics
import Foundation
import WebKit

@MainActor
public final class RenderEngine {
  public init() {}

  public func render(
    html source: HTMLSource,
    stylesheets: [CSSSource] = []
  ) async throws -> Data {
    let document = try RenderDocument(html: source, stylesheets: stylesheets)
    let pageLayout = document.pageLayout
    let contentPageRect = CGRect(origin: .zero, size: pageLayout.contentRect.size)
    let webView = WKWebView(frame: contentPageRect)
    let navigationObserver = WebViewNavigationObserver()

    try await navigationObserver.load(
      document.html,
      baseURL: document.baseURL,
      in: webView
    )

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

    let textLineRanges = try await textLineRanges(in: webView)
    let pageSlices = pageSlices(
      contentHeight: contentHeight,
      pageSize: contentPageRect.size,
      textLineRanges: textLineRanges
    )
    var pages: [Data] = []
    pages.reserveCapacity(pageSlices.count)
    for pageSlice in pageSlices {
      let configuration = WKPDFConfiguration()
      configuration.rect = pageSlice
      pages.append(try await webView.pdf(configuration: configuration))
    }

    return try combine(pages, pageLayout: pageLayout)
  }

  private static let pageBoundaryTolerance: CGFloat = 0.5

  private func textLineRanges(in webView: WKWebView) async throws -> [VerticalRange] {
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

  private func pageSlices(
    contentHeight: CGFloat,
    pageSize: CGSize,
    textLineRanges: [VerticalRange]
  ) -> [CGRect] {
    var slices: [CGRect] = []
    var startY: CGFloat = 0

    while contentHeight - startY > Self.pageBoundaryTolerance {
      let maximumEndY = min(startY + pageSize.height, contentHeight)
      var endY = maximumEndY
      let crossingLineStart =
        textLineRanges
        .filter { $0.minY < maximumEndY && $0.maxY > maximumEndY }
        .map(\.minY)
        .min()

      if maximumEndY < contentHeight,
        let safeEndY = crossingLineStart,
        safeEndY - startY > Self.pageBoundaryTolerance
      {
        endY = safeEndY
      }

      slices.append(
        CGRect(
          x: 0,
          y: startY,
          width: pageSize.width,
          height: endY - startY
        )
      )
      startY = endY
    }

    if slices.isEmpty {
      slices.append(CGRect(origin: .zero, size: pageSize))
    }
    return slices
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

  private func combine(_ pages: [Data], pageLayout: PageLayout) throws -> Data {
    let output = NSMutableData()
    guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
      throw PDFMercuryError.couldNotCreatePDF
    }
    var mediaBox = pageLayout.pageRect
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
      throw PDFMercuryError.couldNotCreatePDF
    }

    for data in pages {
      guard
        let provider = CGDataProvider(data: data as CFData),
        let document = CGPDFDocument(provider),
        let page = document.page(at: 1)
      else {
        throw PDFMercuryError.invalidRenderedPDF
      }

      context.beginPDFPage(nil)
      context.saveGState()
      let renderedPageRect = page.getBoxRect(.mediaBox)
      context.clip(to: pageLayout.contentRect)
      context.translateBy(
        x: pageLayout.contentRect.minX - renderedPageRect.minX,
        y: pageLayout.contentRect.maxY - renderedPageRect.maxY
      )
      context.drawPDFPage(page)
      context.restoreGState()
      context.endPDFPage()
    }

    context.closePDF()
    return output as Data
  }
}

private struct VerticalRange {
  let minY: CGFloat
  let maxY: CGFloat
}

private struct RenderDocument {
  let html: String
  let baseURL: URL?
  let pageLayout: PageLayout

  init(html source: HTMLSource, stylesheets: [CSSSource]) throws {
    let resolvedHTML = try Self.resolve(source)
    let resolvedStylesheets = try stylesheets.map(Self.resolve)
    let resolvedPageLayout = Self.pageLayout(
      for: resolvedStylesheets.map(\.contents).joined(separator: "\n")
    )
    let viewport = """
      <meta name="viewport" content="width=\(resolvedPageLayout.contentRect.width), initial-scale=1.0">
      """

    html = Self.inject(
      ([viewport] + resolvedStylesheets.map(\.htmlElement)).joined(separator: "\n"),
      into: resolvedHTML.contents
    )
    baseURL = resolvedHTML.baseURL
    pageLayout = resolvedPageLayout
  }

  private static func resolve(_ source: HTMLSource) throws -> ResolvedHTML {
    switch source {
    case .string(let contents, let baseURL):
      return ResolvedHTML(contents: contents, baseURL: baseURL)
    case .file(let url):
      guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
        throw PDFMercuryError.unreadableHTMLFile(url)
      }
      return ResolvedHTML(
        contents: contents,
        baseURL: url.deletingLastPathComponent()
      )
    }
  }

  private static func resolve(_ source: CSSSource) throws -> ResolvedStylesheet {
    switch source {
    case .string(let contents):
      return ResolvedStylesheet(
        contents: contents,
        htmlElement: "<style>\n\(contents)\n</style>"
      )
    case .file(let url):
      guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
        throw PDFMercuryError.unreadableCSSFile(url)
      }
      return ResolvedStylesheet(
        contents: contents,
        htmlElement: "<style>\n\(contents)\n</style>"
      )
    }
  }

  private static func inject(_ stylesheets: String, into html: String) -> String {
    guard !stylesheets.isEmpty else { return html }
    guard let closingHead = html.range(of: "</head>", options: .caseInsensitive) else {
      return "<head>\n\(stylesheets)\n</head>\n\(html)"
    }

    var result = html
    result.insert(contentsOf: "\n\(stylesheets)\n", at: closingHead.lowerBound)
    return result
  }

  private static func pageLayout(for css: String) -> PageLayout {
    let a4Portrait = CGSize(width: 595.28, height: 841.89)
    var orientation = PageOrientation.portrait
    var margins = PageMargins.zero

    for pageRule in pageDeclarations(in: css) {
      for declaration in declarations(in: pageRule) {
        switch declaration.name {
        case "size":
          orientation = declaration.value.contains("landscape") ? .landscape : .portrait
        case "margin":
          if let resolvedMargins = PageMargins(cssValue: declaration.value) {
            margins = resolvedMargins
          }
        case "margin-top":
          margins.top = cssLength(declaration.value) ?? margins.top
        case "margin-right":
          margins.right = cssLength(declaration.value) ?? margins.right
        case "margin-bottom":
          margins.bottom = cssLength(declaration.value) ?? margins.bottom
        case "margin-left":
          margins.left = cssLength(declaration.value) ?? margins.left
        default:
          break
        }
      }
    }

    let size =
      orientation == .landscape
      ? CGSize(width: a4Portrait.height, height: a4Portrait.width)
      : a4Portrait
    return PageLayout(pageSize: size, margins: margins)
  }

  private static func pageDeclarations(in css: String) -> [String] {
    let lowercaseCSS = css.lowercased()
    var rules: [String] = []
    var searchStart = lowercaseCSS.startIndex

    while let pageRule = lowercaseCSS.range(
      of: "@page",
      range: searchStart..<lowercaseCSS.endIndex
    ),
      let openingBrace = lowercaseCSS[pageRule.upperBound...].firstIndex(of: "{"),
      let closingBrace = lowercaseCSS[openingBrace...].firstIndex(of: "}")
    {
      rules.append(String(lowercaseCSS[openingBrace...closingBrace]))
      searchStart = lowercaseCSS.index(after: closingBrace)
    }

    return rules
  }

  private static func declarations(in pageRule: String) -> [(name: String, value: String)] {
    pageRule
      .dropFirst()
      .dropLast()
      .split(separator: ";")
      .compactMap { declaration in
        guard let separator = declaration.firstIndex(of: ":") else { return nil }
        let name = declaration[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = declaration[declaration.index(after: separator)...]
          .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, value)
      }
  }

  fileprivate static func cssLength(_ value: String) -> CGFloat? {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value == "0" { return 0 }

    let units: [(suffix: String, factor: Double)] = [
      ("px", 1),
      ("pt", 96 / 72),
      ("in", 96),
      ("cm", 96 / 2.54),
      ("mm", 96 / 25.4),
    ]
    guard let unit = units.first(where: { value.hasSuffix($0.suffix) }) else {
      return nil
    }
    guard let number = Double(value.dropLast(unit.suffix.count)), number >= 0 else {
      return nil
    }
    return CGFloat(number * unit.factor)
  }
}

private enum PageOrientation {
  case portrait
  case landscape
}

private struct PageLayout {
  let pageRect: CGRect
  let contentRect: CGRect

  init(pageSize: CGSize, margins: PageMargins) {
    pageRect = CGRect(origin: .zero, size: pageSize)
    contentRect = CGRect(
      x: margins.left,
      y: margins.bottom,
      width: max(1, pageSize.width - margins.left - margins.right),
      height: max(1, pageSize.height - margins.top - margins.bottom)
    )
  }
}

private struct PageMargins {
  var top: CGFloat
  var right: CGFloat
  var bottom: CGFloat
  var left: CGFloat

  static let zero = PageMargins(top: 0, right: 0, bottom: 0, left: 0)

  init?(cssValue: String) {
    let values =
      cssValue
      .split(whereSeparator: \.isWhitespace)
      .compactMap { RenderDocument.cssLength(String($0)) }
    guard values.count == cssValue.split(whereSeparator: \.isWhitespace).count else {
      return nil
    }

    switch values.count {
    case 1:
      self.init(top: values[0], right: values[0], bottom: values[0], left: values[0])
    case 2:
      self.init(top: values[0], right: values[1], bottom: values[0], left: values[1])
    case 3:
      self.init(top: values[0], right: values[1], bottom: values[2], left: values[1])
    case 4:
      self.init(top: values[0], right: values[1], bottom: values[2], left: values[3])
    default:
      return nil
    }
  }

  private init(top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat) {
    self.top = top
    self.right = right
    self.bottom = bottom
    self.left = left
  }
}

private struct ResolvedHTML {
  let contents: String
  let baseURL: URL?
}

private struct ResolvedStylesheet {
  let contents: String
  let htmlElement: String
}

@MainActor
private final class WebViewNavigationObserver: NSObject, WKNavigationDelegate {
  private var continuation: CheckedContinuation<Void, Error>?

  func load(_ html: String, baseURL: URL?, in webView: WKWebView) async throws {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      webView.navigationDelegate = self
      webView.loadHTMLString(html, baseURL: baseURL)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
    resume(with: .success(()))
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation?,
    withError error: Error
  ) {
    resume(with: .failure(PDFMercuryError.webContentFailedToLoad(error.localizedDescription)))
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation?,
    withError error: Error
  ) {
    resume(with: .failure(PDFMercuryError.webContentFailedToLoad(error.localizedDescription)))
  }

  private func resume(with result: Result<Void, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(with: result)
  }
}
