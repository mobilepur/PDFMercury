import WebKit

@MainActor
final class WebViewNavigationObserver: NSObject, WKNavigationDelegate {
  private var continuation: CheckedContinuation<Void, Error>?
  private var navigation: WKNavigation?

  func load(_ html: String, baseURL: URL?, in webView: WKWebView) async throws {
    try Task.checkCancellation()
    defer { webView.navigationDelegate = nil }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        webView.navigationDelegate = self
        navigation = webView.loadHTMLString(html, baseURL: baseURL)
      }
    } onCancel: {
      Task { @MainActor in
        self.resume(with: .failure(CancellationError()))
        webView.stopLoading()
      }
    }
    try Task.checkCancellation()
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
    guard let active = self.navigation, navigation === active else { return }
    resume(with: .success(()))
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
    guard let active = self.navigation, navigation === active else { return }
    resume(with: .failure(PDFMercuryError.webContentFailedToLoad(error.localizedDescription)))
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
    guard let active = self.navigation, navigation === active else { return }
    resume(with: .failure(PDFMercuryError.webContentFailedToLoad(error.localizedDescription)))
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    resume(with: .failure(PDFMercuryError.webContentFailedToLoad("The WebKit content process terminated.")))
  }

  private func resume(with result: Result<Void, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    navigation = nil
    continuation.resume(with: result)
  }
}
