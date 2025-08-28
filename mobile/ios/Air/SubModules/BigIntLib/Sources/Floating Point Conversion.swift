//
//  Floating Point Conversion.swift
//  BigInt
//
//  Created by Károly Lőrentey on 2017-08-11.
//  Copyright © 2016-2017 Károly Lőrentey.
//

#if canImport(Foundation)
import Foundation
#endif

extension BigUInt {
    public init?<T: BinaryFloatingPoint>(exactly source: T) {
        guard source.isFinite else { return nil }
        guard !source.isZero else { self = 0; return }
        guard source.sign == .plus else { return nil }
        let value = source.rounded(.towardZero)
        guard value == source else { return nil }
        assert(value.floatingPointClass == .positiveNormal)
        assert(value.exponent >= 0)
        let significand = value.significandBitPattern
        self = (BigUInt(1) << value.exponent) + BigUInt(significand) >> (T.significandBitCount - Int(value.exponent))
    }

    public init<T: BinaryFloatingPoint>(_ source: T) {
        self.init(exactly: source.rounded(.towardZero))!
    }

    #if canImport(Foundation)
    public init?(exactly source: Decimal) {
        guard source.exponent >= 0 else { return nil }
        self.init(commonDecimal: source)
    }

    public init?(truncating source: Decimal) {
        self.init(commonDecimal: source)
    }

    private init?(commonDecimal source: Decimal) {
        var integer = source
        if source.exponent < 0 {
            var source = source
            NSDecimalRound(&integer, &source, 0, .down)
        }

        guard !integer.isZero else { self = 0; return }
        guard integer.isFinite else { return nil }
        guard integer.sign == .plus else { return nil }
        assert(integer.floatingPointClass == .positiveNormal)

        #if os(Linux)
        // `Decimal._mantissa` has an internal access level on linux, and it might get
        // deprecated in the future, so keeping the string implementation around for now.
        let significand = BigUInt("\(integer.significand)")!
        #else
        let significand = {
            var start = BigUInt(0)
            for (place, value) in integer.significand.mantissaParts.enumerated() {
                guard value > 0 else { continue }
                start += (1 << (place * 16)) * BigUInt(value)
            }
            return start
        }()
        #endif
        let exponent = BigUInt(10).power(integer.exponent)

        self = significand * exponent
    }
    #endif
}

extension BigInt {
    public init?<T: BinaryFloatingPoint>(exactly source: T) {
        guard let magnitude = BigUInt(exactly: source.magnitude) else { return nil }
        let sign = BigInt.Sign(source.sign)
        self.init(sign: sign, magnitude: magnitude)
    }

    public init<T: BinaryFloatingPoint>(_ source: T) {
        self.init(exactly: source.rounded(.towardZero))!
    }

    #if canImport(Foundation)
    public init?(exactly source: Decimal) {
        guard let magnitude = BigUInt(exactly: source.magnitude) else { return nil }
        let sign = BigInt.Sign(source.sign)
        self.init(sign: sign, magnitude: magnitude)
    }

    public init?(truncating source: Decimal) {
        guard let magnitude = BigUInt(truncating: source.magnitude) else { return nil }
        let sign = BigInt.Sign(source.sign)
        self.init(sign: sign, magnitude: magnitude)
    }
    #endif
}

extension BinaryFloatingPoint where RawExponent: FixedWidthInteger, RawSignificand: FixedWidthInteger {
    public init(_ value: BigInt) {
        guard !value.isZero else { self = 0; return }
        let v = value.magnitude
        let bitWidth = v.bitWidth
        var exponent = bitWidth - 1
        let shift = bitWidth - Self.significandBitCount - 1
        var significand = value.magnitude >> (shift - 1)
        if significand[0] & 3 == 3 { // Handle rounding
            significand >>= 1
            significand += 1
            if significand.trailingZeroBitCount >= Self.significandBitCount {
                exponent += 1
            }
        }
        else {
            significand >>= 1
        }
        let bias = 1 << (Self.exponentBitCount - 1) - 1
        guard exponent <= bias else { self = Self.infinity; return }
        significand &= 1 << Self.significandBitCount - 1
        self = Self.init(sign: value.sign == .plus ? .plus : .minus,
                         exponentBitPattern: RawExponent(bias + exponent),
                         significandBitPattern: RawSignificand(significand))
    }

    public init(_ value: BigUInt) {
        self.init(BigInt(sign: .plus, magnitude: value))
    }
}

extension BigInt.Sign {
    public init(_ sign: FloatingPointSign) {
        switch sign {
        case .plus:
            self = .plus
        case .minus:
            self = .minus
        }
    }
}

#if canImport(Foundation)
public extension Decimal {
    init(_ value: BigUInt) {
        guard
            value < BigUInt(exactly: Decimal.greatestFiniteMagnitude)!
        else {
            self = .greatestFiniteMagnitude
            return
        }
        guard !value.isZero else { self = 0; return }

        self.init(string: "\(value)")!
    }

    init(_ value: BigInt) {
        if value >= 0 {
            self.init(BigUInt(value))
        } else {
            self.init(value.magnitude)
            self *= -1
        }
    }
}
#endif

#if canImport(Foundation) && !os(Linux)
private extension Decimal {
    var mantissaParts: [UInt16] {
        [
            _mantissa.0,
            _mantissa.1,
            _mantissa.2,
            _mantissa.3,
            _mantissa.4,
            _mantissa.5,
            _mantissa.6,
            _mantissa.7,
        ]
    }
}
#endif
