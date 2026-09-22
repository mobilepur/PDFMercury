import Foundation

/// Renders HTML using a reusable WebKit session and a background PDF worker.
@MainActor
public final class RenderEngine {
  public init() {}

  public func render(
    html source: HTMLSource,
    stylesheets: [CSSSource] = [],
    pageFooter: PageFooter? = nil
  ) async throws -> Data {
    let document = try await PDFWorkQueue.perform {
      try RenderDocument(html: source, stylesheets: stylesheets)
    }
    let pool = WebRenderSessionPool.shared
    let session = try await pool.acquire()
    do {
      try Task.checkCancellation()
      let data = try await session.render(document: document, pageFooter: pageFooter)
      try Task.checkCancellation()
      pool.release(session)
      return data
    } catch {
      // A failed or cancelled navigation must never leak into the next document.
      pool.release(nil)
      throw error
    }
  }
}
