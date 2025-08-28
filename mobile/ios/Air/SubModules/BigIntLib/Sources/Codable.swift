//
//  Codable.swift
//  BigInt
//
//  Created by Károly Lőrentey on 2017-8-11.
//  Copyright © 2016-2017 Károly Lőrentey.
//


// Little-endian to big-endian
struct Units<Unit: FixedWidthInteger, Words: RandomAccessCollection>: RandomAccessCollection
where Words.Element: FixedWidthInteger, Words.Index == Int {
    typealias Word = Words.Element
    let words: Words
    init(of type: Unit.Type, _ words: Words) {
        precondition(Word.bitWidth % Unit.bitWidth == 0 || Unit.bitWidth % Word.bitWidth == 0)
        self.words = words
    }
    var count: Int { return (words.count * Word.bitWidth + Unit.bitWidth - 1) / Unit.bitWidth }
    var startIndex: Int { return 0 }
    var endIndex: Int { return count }
    subscript(_ index: Int) -> Unit {
        let index = count - 1 - index
        if Unit.bitWidth == Word.bitWidth {
            return Unit(words[index])
        }
        else if Unit.bitWidth > Word.bitWidth {
            let c = Unit.bitWidth / Word.bitWidth
            var unit: Unit = 0
            var j = 0
            for i in (c * index) ..< Swift.min(c * (index + 1), words.endIndex) {
                unit |= Unit(words[i]) << j
                j += Word.bitWidth
            }
            return unit
        }
        // Unit.bitWidth < Word.bitWidth
        let c = Word.bitWidth / Unit.bitWidth
        let i = index / c
        let j = index % c
        return Unit(truncatingIfNeeded: words[i] >> (j * Unit.bitWidth))
    }
}

extension Array where Element: FixedWidthInteger {
    // Big-endian to little-endian
    init<Unit: FixedWidthInteger>(count: Int?, generator: () throws -> Unit?) rethrows {
        typealias Word = Element
        precondition(Word.bitWidth % Unit.bitWidth == 0 || Unit.bitWidth % Word.bitWidth == 0)
        self = []
        if Unit.bitWidth == Word.bitWidth {
            if let count = count {
                self.reserveCapacity(count)
            }
            while let unit = try generator() {
                self.append(Word(unit))
            }
        }
        else if Unit.bitWidth > Word.bitWidth {
            let wordsPerUnit = Unit.bitWidth / Word.bitWidth
            if let count = count {
                self.reserveCapacity(count * wordsPerUnit)
            }
            while let unit = try generator() {
                var shift = Unit.bitWidth - Word.bitWidth
                while shift >= 0 {
                    self.append(Word(truncatingIfNeeded: unit >> shift))
                    shift -= Word.bitWidth
                }
            }
        }
        else {
            let unitsPerWord = Word.bitWidth / Unit.bitWidth
            if let count = count {
                self.reserveCapacity((count + unitsPerWord - 1) / unitsPerWord)
            }
            var word: Word = 0
            var c = 0
            while let unit = try generator() {
                word <<= Unit.bitWidth
                word |= Word(unit)
                c += Unit.bitWidth
                if c == Word.bitWidth {
                    self.append(word)
                    word = 0
                    c = 0
                }
            }
            if c > 0 {
                self.append(word << c)
                var shifted: Word = 0
                for i in self.indices {
                    let word = self[i]
                    self[i] = shifted | (word >> c)
                    shifted = word << (Word.bitWidth - c)
                }
            }
        }
        self.reverse()
    }
}

extension BigInt: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let valueString = string.split(separator: ":", maxSplits: 1).last else {
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "Tried to decode empty string as BigInt"))
        }
        guard let value = BigInt(valueString) else {
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "Failed to parse string as BigInt"))
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let string = "bigint:\(self)"
        try container.encode(string)
    }
}

extension BigUInt: Codable {
    public init(from decoder: Decoder) throws {
        let value = try BigInt(from: decoder)
        guard value.sign == .plus else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "BigUInt cannot hold a negative value"))
        }
        self = value.magnitude
    }

    public func encode(to encoder: Encoder) throws {
        try BigInt(sign: .plus, magnitude: self).encode(to: encoder)
    }
}
