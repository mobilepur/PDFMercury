import Foundation
@testable import PDFMercury
import Testing
import WebKit

@Suite("Render scheduling", .serialized, .timeLimit(.minutes(1)))
@MainActor
struct RenderSchedulingTests {
  @Test("Synchronous PDF work leaves the main actor available")
  func backgroundWorker() async throws {
    let (started, signal) = AsyncStream<Void>.makeStream()
    let resume = DispatchSemaphore(value: 0)
    let work = Task { @MainActor in
      try await PDFWorkQueue.perform {
        let isMainThread = Thread.isMainThread
        signal.yield(())
        signal.finish()
        // A broken main-thread implementation times out rather than deadlocking.
        let mainActorResponded = resume.wait(timeout: .now() + 5) == .success
        return (isMainThread, mainActorResponded)
      }
    }
    for await _ in started { break }
    resume.signal()
    let (isMainThread, mainActorResponded) = try await work.value
    #expect(!isMainThread)
    #expect(mainActorResponded)
  }

  @Test("Cancelling a waiting lease does not block the next request")
  func cancelledWaiter() async throws {
    let pool = WebRenderSessionPool()
    let first = try await pool.acquire()
    let waiting = Task { @MainActor in try await pool.acquire() }
    await Task.yield()
    waiting.cancel()
    do {
      _ = try await waiting.value
      Issue.record("A cancelled waiter acquired the occupied session")
    } catch is CancellationError {}
    pool.release(first)
    let next = try await pool.acquire()
    #expect(next === first)
    pool.release(next)
  }

  @Test("Cancellation stops navigation even when an asset never finishes loading")
  func cancelledNavigation() async throws {
    let (started, signal) = AsyncStream<Void>.makeStream()
    let handler = UnfinishedAssetHandler(started: signal)
    let configuration = WKWebViewConfiguration()
    configuration.setURLSchemeHandler(handler, forURLScheme: "delayed")
    let webView = WKWebView(frame: .zero, configuration: configuration)
    let observer = WebViewNavigationObserver()
    let loading = Task { @MainActor in
      try await observer.load(
        "<html><body><img src='delayed://fixture/image'></body></html>",
        baseURL: nil, in: webView
      )
    }
    for await _ in started { break }
    loading.cancel()
    do {
      try await loading.value
      Issue.record("Expected interrupted navigation to throw CancellationError")
    } catch is CancellationError {}
    #expect(webView.navigationDelegate == nil)
    // A fresh load with the same observer cannot resume the old continuation.
    try await observer.load("<p>Recovered</p>", baseURL: nil, in: webView)
  }
}

@MainActor
private final class UnfinishedAssetHandler: NSObject, WKURLSchemeHandler {
  let started: AsyncStream<Void>.Continuation

  init(started: AsyncStream<Void>.Continuation) {
    self.started = started
  }

  func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
    started.yield(())
    started.finish()
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
