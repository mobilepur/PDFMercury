import CoreGraphics
import Foundation
import WebKit

@MainActor
final class PageFooterRenderer {
  private let webView: WKWebView
  private let width: CGFloat

  init(source: WKWebView, configuration: PageFooter, baseURL: URL?, size: CGSize) async throws {
    guard !configuration.elementID.isEmpty, configuration.gap.isFinite, configuration.gap >= 0 else {
      throw PDFMercuryError.invalidPageFooter("The element ID must be nonempty and the gap finite and nonnegative.")
    }
    self.width = size.width
    webView = WKWebView(frame: CGRect(origin: .zero, size: size))
    let result = try await source.callAsyncJavaScript("""
      const matches = Array.from(document.querySelectorAll('[id]')).filter(e => e.id === elementID);
      if (matches.length !== 1) return {error: 'Expected exactly one element with the requested ID.'};
      const footer = matches[0];
      const style = getComputedStyle(footer);
      if (footer.parentElement !== document.body) return {error: 'The footer must be a direct child of body.'};
      if (style.position === 'absolute' || style.position === 'fixed' || style.display === 'none'
          || style.visibility !== 'visible' || footer.getBoundingClientRect().height <= 0)
        return {error: 'The footer must be visible and in normal flow.'};
      const copy = document.documentElement.cloneNode(true);
      const body = copy.querySelector('body');
      const footerCopy = footer.cloneNode(true);
      body.replaceChildren(footerCopy);
      // Retain horizontal body insets so the footer aligns with the body text.
      // Remove vertical layout constraints and decorative top/bottom borders.
      for (const element of [copy, body]) {
        for (const [key, value] of Object.entries({'margin-top':'0', 'margin-bottom':'0',
          'padding-top':'0', 'padding-bottom':'0', 'border-top-width':'0', 'border-bottom-width':'0', height:'auto',
          'min-height':'0', 'max-height':'none', width:'auto', 'min-width':'0',
          'max-width':'none', position:'static', display:'block', overflow:'hidden'}))
          element.style.setProperty(key, value, 'important');
      }
      // Mobile WebKit rounds viewport widths to whole CSS pixels. Keep the
      // copied document within the actual, potentially fractional PDF width.
      copy.style.setProperty('box-sizing', 'border-box', 'important');
      copy.style.setProperty('max-width', String(width) + 'px', 'important');
      body.style.setProperty('display', 'flow-root', 'important');
      footerCopy.style.setProperty('margin', '0', 'important');
      for (const script of copy.querySelectorAll('script')) script.remove();
      footer.remove();
      return {html: '<!doctype html>' + copy.outerHTML};
      """, arguments: ["elementID": configuration.elementID, "width": Double(width)], in: nil, contentWorld: .page)
    guard let response = result as? [String: String] else {
      throw PDFMercuryError.invalidPageFooter("Could not extract the footer element.")
    }
    if let error = response["error"] { throw PDFMercuryError.invalidPageFooter(error) }
    guard let html = response["html"] else {
      throw PDFMercuryError.invalidPageFooter("Could not extract the footer HTML.")
    }
    let observer = WebViewNavigationObserver()
    try await observer.load(html, baseURL: baseURL, in: webView)
  }

  func height(pageNumber: Int, pageCount: Int) async throws -> CGFloat {
    let result = try await webView.callAsyncJavaScript("""
      for (const element of document.querySelectorAll('[data-pdf-page-number]')) element.textContent = String(pageNumber);
      for (const element of document.querySelectorAll('[data-pdf-page-count]')) element.textContent = String(pageCount);
      await document.fonts.ready;
      const footer = document.body.firstElementChild;
      const rect = footer.getBoundingClientRect();
      if (rect.height <= 0 || rect.top < -0.1 || rect.left < -0.1
          || rect.right > width + 0.1 || footer.scrollWidth > rect.width + 1
          || footer.scrollHeight > rect.height + 1)
        return -1;
      // Positioned or transformed descendants can paint outside the measured box.
      for (const child of footer.querySelectorAll('*')) {
        const childRect = child.getBoundingClientRect();
        if (childRect.width && childRect.height && (childRect.top < rect.top - 0.1
            || childRect.bottom > rect.bottom + 0.1 || childRect.left < -0.1 || childRect.right > width + 0.1)) return -1;
      }
      return rect.bottom;
      """, arguments: ["pageNumber": pageNumber, "pageCount": pageCount, "width": Double(width)],
      in: nil, contentWorld: .page)
    guard let number = result as? NSNumber, number.doubleValue.isFinite, number.doubleValue > 0 else {
      throw PDFMercuryError.invalidPageFooter("The footer must have a positive height and fit its content without overflow.")
    }
    return CGFloat(number.doubleValue)
  }

  func render(pageNumber: Int, pageCount: Int, maximumHeight: CGFloat) async throws -> (Data, CGFloat) {
    let height = try await height(pageNumber: pageNumber, pageCount: pageCount)
    guard height <= maximumHeight + 0.1 else {
      throw PDFMercuryError.invalidPageFooter("The footer changed height after pagination.")
    }
    let configuration = WKPDFConfiguration()
    configuration.rect = CGRect(x: 0, y: 0, width: width, height: height)
    return (try await webView.pdf(configuration: configuration), height)
  }
}
