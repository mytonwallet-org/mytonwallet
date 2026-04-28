import Compression
import Foundation

enum AnimationCompression {
    static func alignUp(_ value: Int, to alignment: Int) -> Int {
        precondition(alignment > 0)
        return ((value + alignment - 1) / alignment) * alignment
    }

    static func compressLZFSE(_ sourceData: Data) -> Data? {
        sourceData.withUnsafeBytes { sourceBuffer in
            Self.compressLZFSE(sourceBuffer)
        }
    }

    static func compressLZFSE(_ sourceBuffer: UnsafeRawBufferPointer) -> Data? {
        guard let sourceBase = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let scratchSize = compression_encode_scratch_buffer_size(COMPRESSION_LZFSE)
        let scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: scratchSize)
        defer {
            scratch.deallocate()
        }

        var destinationCapacity = max(sourceBuffer.count + 1024, 4 * 1024)
        for _ in 0 ..< 6 {
            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationCapacity)
            let encodedSize = compression_encode_buffer(
                destination,
                destinationCapacity,
                sourceBase,
                sourceBuffer.count,
                scratch,
                COMPRESSION_LZFSE
            )
            if encodedSize > 0 {
                return Data(
                    bytesNoCopy: destination,
                    count: encodedSize,
                    deallocator: .custom { pointer, _ in
                        pointer.assumingMemoryBound(to: UInt8.self).deallocate()
                    }
                )
            }
            destination.deallocate()
            destinationCapacity *= 2
        }

        return nil
    }

    static func decompressLZFSE(
        _ compressedData: Data,
        range: Range<Int>,
        into destination: UnsafeMutableRawPointer,
        expectedSize: Int
    ) -> Bool {
        guard range.lowerBound >= 0, range.upperBound <= compressedData.count else {
            return false
        }

        return compressedData.withUnsafeBytes { sourceBuffer in
            guard let sourceBase = sourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return false
            }

            let scratchSize = compression_decode_scratch_buffer_size(COMPRESSION_LZFSE)
            let scratch = UnsafeMutablePointer<UInt8>.allocate(capacity: scratchSize)
            defer {
                scratch.deallocate()
            }

            let decodedSize = compression_decode_buffer(
                destination.assumingMemoryBound(to: UInt8.self),
                expectedSize,
                sourceBase.advanced(by: range.lowerBound),
                range.count,
                scratch,
                COMPRESSION_LZFSE
            )
            return decodedSize == expectedSize
        }
    }
}

extension Data {
    mutating func appendInteger<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            self.append(contentsOf: bytes)
        }
    }
}
