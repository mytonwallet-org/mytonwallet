import Foundation
import WalletContext

/// Keeps native text edits decimal and lossless until they enter the shared quote pipeline.
public struct TradeAmountInput: Equatable {
    public private(set) var text: String

    public init(text: String = "") { self.text = text }

    public mutating func set(_ amount: BigInt, decimals: Int) {
        self = Self(text: amount > 0 ? bigIntToDoubleString(amount, decimals: decimals) : "")
    }

    public func amount(decimals: Int) -> BigInt {
        normalizedAmountValue(text, digits: decimals)
    }

    public struct Edit {
        public let input: TradeAmountInput
        public let caret: Int
    }

    public func replacing(_ range: NSRange, with replacement: String, decimals: Int) -> Edit? {
        guard let swiftRange = Range(range, in: text) else { return nil }
        let replacement = replacement.normalizeArabicPersianNumeralStringToWestern()
        let allowed = CharacterSet(charactersIn: "0123456789., '\u{00A0}\u{202F}\u{2009}’")
        guard replacement.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        if replacement == "." || replacement == "," {
            guard !text.replacingCharacters(in: swiftRange, with: "").contains(".") else { return nil }
        }
        let raw = text.replacingCharacters(in: swiftRange, with: replacement)
        let normalized = normalizeAmountInput(raw, preserveTrailingSeparator: true)
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard (parts.first?.count ?? 0) <= 12,
              parts.count < 2 || (decimals > 0 && parts[1].count <= decimals) else { return nil }

        // Map the insertion point through removed grouping characters and leading zeroes.
        let rawCaret = range.location + replacement.utf16.count
        let separator = raw.lastIndex { $0 == "." || $0 == "," }
        let prefix = String(decoding: raw.utf16.prefix(rawCaret), as: UTF16.self)
        var caret = prefix.filter(\.isWholeNumber).count
        if let separator, raw.distance(from: raw.startIndex, to: separator) < prefix.count { caret += 1 }
        if raw.first == "." || raw.first == "," { caret += 1 }
        let integral = String(parts.first ?? "")
        let trimmed = integral.drop { $0 == "0" }
        let removedZeros = integral.count - max(1, trimmed.count)
        let result = String(normalized.dropFirst(max(0, removedZeros)))
        caret = min(result.utf16.count, max(0, caret - max(0, removedZeros)))
        return Edit(input: TradeAmountInput(text: result), caret: caret)
    }

}
