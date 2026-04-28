import Foundation

enum AnimationFrameCacheFormat {
    static let magic: UInt32 = 0x4352464C // LFRC
    static let version: UInt32 = 1
}

struct AnimationFrameCacheEntry: Sendable {
    let offset: UInt64
    let compressedSize: UInt32
}

final class AnimationFrameCacheAsset: Sendable {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let frameCount: Int
    let frameRate: Int
    let fileSizeBytes: Int64

    private let mappedData: Data
    private let entries: [AnimationFrameCacheEntry]

    private init(
        mappedData: Data,
        entries: [AnimationFrameCacheEntry],
        width: Int,
        height: Int,
        bytesPerRow: Int,
        frameCount: Int,
        frameRate: Int,
        fileSizeBytes: Int64
    ) {
        self.mappedData = mappedData
        self.entries = entries
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.frameCount = frameCount
        self.frameRate = frameRate
        self.fileSizeBytes = fileSizeBytes
    }

    static func load(url: URL) -> AnimationFrameCacheAsset? {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let fileSizeValue = attributes[.size] as? NSNumber,
            let mappedData = try? Data(contentsOf: url, options: [.mappedIfSafe])
        else {
            return nil
        }

        var cursor = 0
        guard
            let magic = Self.readUInt32(from: mappedData, cursor: &cursor),
            magic == AnimationFrameCacheFormat.magic,
            let version = Self.readUInt32(from: mappedData, cursor: &cursor),
            version == AnimationFrameCacheFormat.version,
            let width = Self.readUInt32(from: mappedData, cursor: &cursor),
            let height = Self.readUInt32(from: mappedData, cursor: &cursor),
            let bytesPerRow = Self.readUInt32(from: mappedData, cursor: &cursor),
            let frameCount = Self.readUInt32(from: mappedData, cursor: &cursor),
            let frameRate = Self.readUInt32(from: mappedData, cursor: &cursor)
        else {
            return nil
        }

        var entries: [AnimationFrameCacheEntry] = []
        entries.reserveCapacity(Int(frameCount))
        for _ in 0 ..< frameCount {
            guard
                let offset = Self.readUInt64(from: mappedData, cursor: &cursor),
                let compressedSize = Self.readUInt32(from: mappedData, cursor: &cursor),
                Self.readUInt32(from: mappedData, cursor: &cursor) != nil
            else {
                return nil
            }

            entries.append(
                AnimationFrameCacheEntry(
                    offset: offset,
                    compressedSize: compressedSize
                )
            )
        }

        return AnimationFrameCacheAsset(
            mappedData: mappedData,
            entries: entries,
            width: Int(width),
            height: Int(height),
            bytesPerRow: Int(bytesPerRow),
            frameCount: Int(frameCount),
            frameRate: Int(frameRate),
            fileSizeBytes: fileSizeValue.int64Value
        )
    }

    func decodeFrame(index: Int) -> sending AnimationFrameBuffer? {
        guard !self.entries.isEmpty else {
            return nil
        }

        let normalizedIndex = ((index % self.entries.count) + self.entries.count) % self.entries.count
        let entry = self.entries[normalizedIndex]
        let rangeStart = Int(entry.offset)
        let rangeEnd = rangeStart + Int(entry.compressedSize)
        guard rangeStart >= 0, rangeEnd <= self.mappedData.count else {
            return nil
        }

        let frameBuffer = AnimationFrameBuffer(
            width: self.width,
            height: self.height,
            bytesPerRow: self.bytesPerRow
        )
        let didDecode = AnimationCompression.decompressLZFSE(
            self.mappedData,
            range: rangeStart ..< rangeEnd,
            into: UnsafeMutableRawPointer(frameBuffer.bytes),
            expectedSize: frameBuffer.length
        )
        return didDecode ? frameBuffer : nil
    }

    private static func readUInt32(from data: Data, cursor: inout Int) -> UInt32? {
        let length = MemoryLayout<UInt32>.size
        guard cursor + length <= data.count else {
            return nil
        }

        let value = data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: cursor, as: UInt32.self)
        }
        cursor += length
        return UInt32(littleEndian: value)
    }

    private static func readUInt64(from data: Data, cursor: inout Int) -> UInt64? {
        let length = MemoryLayout<UInt64>.size
        guard cursor + length <= data.count else {
            return nil
        }

        let value = data.withUnsafeBytes { buffer in
            buffer.loadUnaligned(fromByteOffset: cursor, as: UInt64.self)
        }
        cursor += length
        return UInt64(littleEndian: value)
    }
}
