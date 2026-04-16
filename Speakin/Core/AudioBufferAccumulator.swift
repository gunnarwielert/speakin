import Foundation

/// Thread-safe accumulator that batches audio buffers to reduce I/O operations.
final class AudioBufferAccumulator {
    private let batchSize: Int
    private var buffers: [(data: Data, frameLength: Int)] = []
    private let lock = NSLock()

    init(batchSize: Int) {
        self.batchSize = batchSize
    }

    /// Appends a buffer and returns `true` when the batch is full and ready to write.
    @discardableResult
    func append(_ data: Data, frameLength: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        buffers.append((data: data, frameLength: frameLength))
        return buffers.count >= batchSize
    }

    /// Extracts and clears all accumulated buffers.
    func extractBatch() -> [(data: Data, frameLength: Int)] {
        lock.lock()
        defer { lock.unlock() }
        let batch = buffers
        buffers.removeAll(keepingCapacity: true)
        return batch
    }

    func isEmpty() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffers.isEmpty
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffers.removeAll(keepingCapacity: false)
    }
}
