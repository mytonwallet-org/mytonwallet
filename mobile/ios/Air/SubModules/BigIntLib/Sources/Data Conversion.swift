//
//  Data Conversion.swift
//  BigInt
//
//  Created by Károly Lőrentey on 2016-01-04.
//  Copyright © 2016-2017 Károly Lőrentey.
//

#if canImport(Foundation)
import Foundation
#endif

extension BigUInt {
    //MARK: NSData Conversion

    /// Initialize a BigInt from bytes accessed from an UnsafeRawBufferPointer
    public init(_ buffer: UnsafeRawBufferPointer) {
        // This assumes Word is binary.
        precondition(Word.bitWidth % 8 == 0)

        self.init()

        let length = buffer.count
        guard length > 0 else { return }
        let bytesPerDigit = Word.bitWidth / 8
        var index = length / bytesPerDigit
        var c = bytesPerDigit - length % bytesPerDigit
        if c == bytesPerDigit {
            c = 0
            index -= 1
        }

        var word: Word = 0
        for byte in buffer {
            word <<= 8
            word += Word(byte)
            c += 1
            if c == bytesPerDigit {
                self[index] = word
                index -= 1
                c = 0
                word = 0
            }
        }
        assert(c == 0 && word == 0 && index == -1)
    }

    /// Return a `UnsafeRawBufferPointer` buffer that contains the base-256 representation of this integer, in network (big-endian) byte order.
    public func serializeToBuffer() -> UnsafeRawBufferPointer {
        // This assumes Digit is binary.
        precondition(Word.bitWidth % 8 == 0)

        let byteCount = (self.bitWidth + 7) / 8

        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: byteCount)

        guard byteCount > 0 else { return UnsafeRawBufferPointer(start: buffer.baseAddress, count: 0) }

        var i = byteCount - 1
        for var word in self.words {
            for _ in 0 ..< Word.bitWidth / 8 {
                buffer[i] = UInt8(word & 0xFF)
                word >>= 8
                if i == 0 {
                    assert(word == 0)
                    break
                }
                i -= 1
            }
        }
        let zeroOut = UnsafeMutableBufferPointer<UInt8>(start: buffer.baseAddress, count: i)
        zeroOut.initialize(repeating: 0)
        return UnsafeRawBufferPointer(start: buffer.baseAddress, count: byteCount)
    }

    #if canImport(Foundation)
    /// Initializes an integer from the bits stored inside a piece of `Data`.
    /// The data is assumed to be in network (big-endian) byte order.
    public init(_ data: Data) {
        self = data.withUnsafeBytes({ buffer in
            BigUInt(buffer)
        })
    }

    /// Return a `Data` value that contains the base-256 representation of this integer, in network (big-endian) byte order.
    public func serialize() -> Data {
        let buffer = serializeToBuffer()
        defer { buffer.deallocate() }
        guard
            let pointer = buffer.baseAddress.map(UnsafeMutableRawPointer.init(mutating:))
        else { return Data() }

        return Data(bytes: pointer, count: buffer.count)
    }
    #endif
}

extension BigInt {
    
    /// Initialize a BigInt from bytes accessed from an UnsafeRawBufferPointer,
    /// where the first byte indicates sign (0 for positive, 1 for negative)
    public init(_ buffer: UnsafeRawBufferPointer) {
        // This assumes Word is binary.
        precondition(Word.bitWidth % 8 == 0)
        
        self.init()
        
        let length = buffer.count
        
        // Serialized data for a BigInt should contain at least 2 bytes: one representing
        // the sign, and another for the non-zero magnitude. Zero is represented by an
        // empty Data struct, and negative zero is not supported.
        guard length > 1, let firstByte = buffer.first else { return }

        // The first byte gives the sign
        // This byte is compared to a bitmask to allow additional functionality to be added
        // to this byte in the future.
        self.sign = firstByte & 0b1 == 0 ? .plus : .minus

        self.magnitude = BigUInt(UnsafeRawBufferPointer(rebasing: buffer.dropFirst(1)))
    }

    /// Return a `Data` value that contains the base-256 representation of this integer, in network (big-endian) byte order and a prepended byte to indicate the sign (0 for positive, 1 for negative)
    public func serializeToBuffer() -> UnsafeRawBufferPointer {
        // Create a data object for the magnitude portion of the BigInt
        let magnitudeBuffer = self.magnitude.serializeToBuffer()

        // Similar to BigUInt, a value of 0 should return an empty buffer
        guard magnitudeBuffer.count > 0 else { return magnitudeBuffer }

        // Create a new buffer for the signed BigInt value
        let newBuffer = UnsafeMutableRawBufferPointer.allocate(byteCount: magnitudeBuffer.count + 1, alignment: 8)
        let magnitudeSection = UnsafeMutableRawBufferPointer(rebasing: newBuffer[1...])
        magnitudeSection.copyBytes(from: magnitudeBuffer)
        magnitudeBuffer.deallocate()

        // The first byte should be 0 for a positive value, or 1 for a negative value
        // i.e., the sign bit is the LSB
        newBuffer[0] = self.sign == .plus ? 0 : 1

        return UnsafeRawBufferPointer(start: newBuffer.baseAddress, count: newBuffer.count)
    }

    #if canImport(Foundation)
    /// Initializes an integer from the bits stored inside a piece of `Data`.
    /// The data is assumed to be in network (big-endian) byte order with a first
    /// byte to represent the sign (0 for positive, 1 for negative)
    public init(_ data: Data) {
        self = data.withUnsafeBytes({ buffer in
            BigInt(buffer)
        })
    }
    
    /// Return a `Data` value that contains the base-256 representation of this integer, in network (big-endian) byte order and a prepended byte to indicate the sign (0 for positive, 1 for negative)
    public func serialize() -> Data {
        let buffer = serializeToBuffer()
        defer { buffer.deallocate() }
        guard
            let pointer = buffer.baseAddress.map(UnsafeMutableRawPointer.init(mutating:))
        else { return Data() }

        return Data(bytes: pointer, count: buffer.count)
    }
    #endif
}
