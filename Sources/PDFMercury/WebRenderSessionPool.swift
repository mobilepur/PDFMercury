import Foundation

/// One process-wide session also serves callers that construct a new engine for
/// every preview. A lease spans all awaits, so document state cannot interleave.
@MainActor
final class WebRenderSessionPool {
  static let shared = WebRenderSessionPool()

  private var idleSession: WebRenderSession?
  private var isLeased = false
  private var waiters: [(id: UUID, continuation: CheckedContinuation<WebRenderSession, Error>)] = []

  func acquire() async throws -> WebRenderSession {
    try Task.checkCancellation()
    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else if !isLeased {
          isLeased = true
          let session = idleSession ?? WebRenderSession()
          idleSession = nil
          continuation.resume(returning: session)
        } else {
          waiters.append((id, continuation))
        }
      }
    } onCancel: {
      Task { @MainActor in
        guard let index = self.waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = self.waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
      }
    }
  }

  /// Pass nil to discard a session after failure or cancellation.
  func release(_ session: WebRenderSession?) {
    precondition(isLeased)
    if waiters.isEmpty {
      idleSession = session
      isLeased = false
    } else {
      let waiter = waiters.removeFirst()
      waiter.continuation.resume(returning: session ?? WebRenderSession())
    }
  }
}
