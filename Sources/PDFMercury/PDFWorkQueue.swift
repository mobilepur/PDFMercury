import Foundation

/// File I/O and Core Graphics are synchronous. Keep them off both the main
/// thread and Swift's cooperative executor; bound memory use with one worker.
enum PDFWorkQueue {
  private static let queue = DispatchQueue(label: "PDFMercury.processing", qos: .userInitiated)

  static func perform<Value: Sendable>(
    _ operation: @escaping @Sendable () throws -> Value
  ) async throws -> Value {
    try Task.checkCancellation()
    let cancellation = WorkCancellation()
    return try await withTaskCancellationHandler {
      let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
        queue.async {
          continuation.resume(with: Result {
            try cancellation.check()
            return try autoreleasepool(invoking: operation)
          })
        }
      }
      // An already running synchronous phase finishes before its result is discarded.
      try Task.checkCancellation()
      return value
    } onCancel: {
      cancellation.cancel()
    }
  }
}

/// Only the flag crosses threads; every access is protected by this lock.
private final class WorkCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var isCancelled = false

  func cancel() {
    lock.lock()
    defer { lock.unlock() }
    isCancelled = true
  }

  func check() throws {
    lock.lock()
    defer { lock.unlock() }
    if isCancelled { throw CancellationError() }
  }
}
