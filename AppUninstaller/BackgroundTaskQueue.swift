import Foundation

/// FIFO execution across suspension points. Cancelled waiting callers never
/// start their operations; running work retains ownership until it finishes.
actor BackgroundTaskQueue {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var isProcessing = false
    private var waiters: [Waiter] = []

    func enqueue<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if isProcessing {
                    waiters.append(Waiter(id: id, continuation: continuation))
                } else {
                    isProcessing = true
                    continuation.resume()
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
        defer { releaseNext() }
        try Task.checkCancellation()
        return try await operation()
    }

    /// Cancels pending work without releasing the currently running operation.
    func cancelAll() {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.continuation.resume(throwing: CancellationError())
        }
    }

    var isCurrentlyProcessing: Bool { isProcessing }
    var pendingCount: Int { waiters.count }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    private func releaseNext() {
        if waiters.isEmpty {
            isProcessing = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }
}
