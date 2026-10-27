import Foundation
import Metal

/// A frame owns its slot until the GPU completes. Exhaustion drops a submission,
/// never blocks the UI or overwrites bytes that an earlier frame is still reading.
final class CardParticleBufferPool: @unchecked Sendable {
    private let lock = NSLock()
    private let buffers: [MTLBuffer]
    private var busy: [Bool]

    init?(device: MTLDevice, length: Int, count: Int = 3) {
        var buffers: [MTLBuffer] = []
        for _ in 0..<count {
            guard let buffer = device.makeBuffer(length: max(1, length), options: .storageModeShared) else { return nil }
            buffers.append(buffer)
        }
        self.buffers = buffers
        busy = Array(repeating: false, count: count)
    }

    func acquire() -> (index: Int, buffer: MTLBuffer)? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = busy.firstIndex(of: false) else { return nil }
        busy[index] = true
        return (index, buffers[index])
    }

    func release(_ index: Int) {
        lock.lock()
        busy[index] = false
        lock.unlock()
    }
}
