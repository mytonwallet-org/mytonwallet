import Foundation

final class AnimationFrameCacheWriter {
    private let outputURL: URL
    private let tempURL: URL
    private let handle: FileHandle
    private let fileManager = FileManager.default

    private let width: Int
    private let height: Int
    private let bytesPerRow: Int
    private let frameCount: Int
    private let frameRate: Int

    private var entries: [AnimationFrameCacheEntry] = []
    private var currentOffset: UInt64
    private var handleClosed = false
    private var committed = false

    init?(
        outputURL: URL,
        frameCount: Int,
        frameRate: Int,
        width: Int,
        height: Int
    ) {
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.bytesPerRow = AnimationCompression.alignUp(width * 4, to: 64)
        self.frameCount = frameCount
        self.frameRate = frameRate

        let outputDirectory = outputURL.deletingLastPathComponent()
        let tempURL = outputDirectory.appendingPathComponent(
            "\(outputURL.lastPathComponent).tmp-\(UUID().uuidString)"
        )
        self.tempURL = tempURL

        do {
            try self.fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            if self.fileManager.fileExists(atPath: tempURL.path) {
                try self.fileManager.removeItem(at: tempURL)
            }
            _ = self.fileManager.createFile(atPath: tempURL.path, contents: nil)
        } catch {
            return nil
        }

        guard let handle = try? FileHandle(forWritingTo: tempURL) else {
            try? self.fileManager.removeItem(at: tempURL)
            return nil
        }
        self.handle = handle

        let headerSize = 7 * MemoryLayout<UInt32>.size
        let entrySize = MemoryLayout<UInt64>.size + 2 * MemoryLayout<UInt32>.size
        let payloadOffset = headerSize + frameCount * entrySize
        self.currentOffset = UInt64(payloadOffset)
        self.entries.reserveCapacity(frameCount)

        do {
            try handle.truncate(atOffset: UInt64(payloadOffset))
            try handle.seek(toOffset: UInt64(payloadOffset))
        } catch {
            try? handle.close()
            try? self.fileManager.removeItem(at: tempURL)
            return nil
        }
    }

    deinit {
        if !self.committed {
            self.cancel()
        }
    }

    func appendFrame(_ frameBuffer: AnimationFrameBuffer) -> Bool {
        guard !self.committed, !self.handleClosed else {
            return false
        }
        guard
            frameBuffer.width == self.width,
            frameBuffer.height == self.height,
            frameBuffer.bytesPerRow == self.bytesPerRow
        else {
            return false
        }
        guard let compressedFrame = frameBuffer.withUnsafeBytes(AnimationCompression.compressLZFSE) else {
            return false
        }

        do {
            try self.handle.write(contentsOf: compressedFrame)
        } catch {
            return false
        }

        self.entries.append(
            AnimationFrameCacheEntry(
                offset: self.currentOffset,
                compressedSize: UInt32(compressedFrame.count)
            )
        )
        self.currentOffset += UInt64(compressedFrame.count)
        return true
    }

    func finish() -> AnimationFrameCacheAsset? {
        guard !self.committed, !self.handleClosed, self.entries.count == self.frameCount else {
            self.cancel()
            return nil
        }

        var headerData = Data()
        headerData.appendInteger(AnimationFrameCacheFormat.magic)
        headerData.appendInteger(AnimationFrameCacheFormat.version)
        headerData.appendInteger(UInt32(self.width))
        headerData.appendInteger(UInt32(self.height))
        headerData.appendInteger(UInt32(self.bytesPerRow))
        headerData.appendInteger(UInt32(self.frameCount))
        headerData.appendInteger(UInt32(self.frameRate))

        let entrySize = MemoryLayout<UInt64>.size + 2 * MemoryLayout<UInt32>.size
        var indexData = Data(capacity: self.entries.count * entrySize)
        for entry in self.entries {
            indexData.appendInteger(entry.offset)
            indexData.appendInteger(entry.compressedSize)
            indexData.appendInteger(UInt32(0))
        }

        do {
            try self.handle.seek(toOffset: 0)
            try self.handle.write(contentsOf: headerData)
            try self.handle.write(contentsOf: indexData)
            try self.handle.close()
            self.handleClosed = true

            if self.fileManager.fileExists(atPath: self.outputURL.path) {
                try self.fileManager.removeItem(at: self.outputURL)
            }
            try self.fileManager.moveItem(at: self.tempURL, to: self.outputURL)
        } catch {
            self.cancel()
            return nil
        }

        self.committed = true
        return AnimationFrameCacheAsset.load(url: self.outputURL)
    }

    func cancel() {
        if !self.handleClosed {
            try? self.handle.close()
            self.handleClosed = true
        }
        if !self.committed, self.fileManager.fileExists(atPath: self.tempURL.path) {
            try? self.fileManager.removeItem(at: self.tempURL)
        }
    }
}
