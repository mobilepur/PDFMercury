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
    let pageRect = document.pageRect
    let webView = WKWebView(frame: pageRect)
    let navigationObserver = WebViewNavigationObserver()

    try await navigationObserver.load(
      document.html,
      baseURL: document.baseURL,
      in: webView
    )

    let contentHeight = try await contentHeight(in: webView)
    let pageCount = max(
      1,
      Int(ceil((contentHeight - Self.pageBoundaryTolerance) / pageRect.height))
    )
    webView.frame = CGRect(
      origin: .zero,
      size: CGSize(
        width: pageRect.width,
        height: CGFloat(pageCount) * pageRect.height
      )
    )

    var pages: [Data] = []
    pages.reserveCapacity(pageCount)
    for pageIndex in 0..<pageCount {
      let configuration = WKPDFConfiguration()
      configuration.rect = pageRect.offsetBy(
        dx: 0,
        dy: CGFloat(pageIndex) * pageRect.height
      )
      pages.append(try await webView.pdf(configuration: configuration))
    }

    return try combine(pages, pageRect: pageRect)
  }

  private static let pageBoundaryTolerance: CGFloat = 0.5

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

  private func combine(_ pages: [Data], pageRect: CGRect) throws -> Data {
    let output = NSMutableData()
    guard let consumer = CGDataConsumer(data: output as CFMutableData) else {
      throw PDFMercuryError.couldNotCreatePDF
    }
    var mediaBox = pageRect
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
      context.drawPDFPage(page)
      context.endPDFPage()
    }

    context.closePDF()
    return output as Data
  }
}

private struct RenderDocument {
  let html: String
  let baseURL: URL?
  let pageRect: CGRect

  init(html source: HTMLSource, stylesheets: [CSSSource]) throws {
    let resolvedHTML = try Self.resolve(source)
    let resolvedStylesheets = try stylesheets.map(Self.resolve)
    let resolvedPageRect = Self.pageRect(
      for: resolvedStylesheets.map(\.contents).joined(separator: "\n")
    )
    let viewport = """
      <meta name="viewport" content="width=\(resolvedPageRect.width), initial-scale=1.0">
      """

    html = Self.inject(
      ([viewport] + resolvedStylesheets.map(\.htmlElement)).joined(separator: "\n"),
      into: resolvedHTML.contents
    )
    baseURL = resolvedHTML.baseURL
    pageRect = resolvedPageRect
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

  private static func pageRect(for css: String) -> CGRect {
    let a4Portrait = CGSize(width: 595.28, height: 841.89)
    let orientation = pageDeclaration(in: css)?.contains("landscape") == true
    let size =
      orientation
      ? CGSize(width: a4Portrait.height, height: a4Portrait.width)
      : a4Portrait
    return CGRect(origin: .zero, size: size)
  }

  private static func pageDeclaration(in css: String) -> String? {
    let lowercaseCSS = css.lowercased()
    guard let pageRule = lowercaseCSS.range(of: "@page") else { return nil }
    guard
      let openingBrace = lowercaseCSS[pageRule.upperBound...].firstIndex(of: "{"),
      let closingBrace = lowercaseCSS[openingBrace...].firstIndex(of: "}")
    else {
      return nil
    }
    return String(lowercaseCSS[openingBrace...closingBrace])
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
