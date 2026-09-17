import Foundation

public struct NormalizedSearchTerm: Hashable, Sendable {
    public let alternatives: [String]

    public init(alternatives: [String]) {
        self.alternatives = alternatives
    }
}

public struct NormalizedSearchText: Hashable, Sendable {
    public let canonical: String
    public let transliterated: String?
    public let terms: [NormalizedSearchTerm]

    public var phraseAlternatives: [String] {
        var values = canonical.isEmpty ? [] : [canonical]
        if let transliterated {
            values.append(transliterated)
        }
        return unique(values)
    }

    public var tokenAlternatives: Set<String> {
        Set(terms.flatMap(\.alternatives))
    }

    public var isEmpty: Bool { canonical.isEmpty }

    private func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

public struct UniversalSearchQuery: Hashable, Sendable {
    public let text: String
    public let normalizedText: NormalizedSearchText
    public let normalizedIdentifier: String

    public init(_ text: String) {
        self.text = text
        self.normalizedText = SearchTextNormalizer.normalize(text)
        self.normalizedIdentifier = SearchTextNormalizer.normalizeIdentifier(text)
    }

    public var isEmpty: Bool { normalizedText.isEmpty }
    public var termCount: Int { normalizedText.terms.count }
    public var isMultiword: Bool {
        termCount > 1 && text.split(whereSeparator: \.isWhitespace).count > 1
    }

    // Keep the complete query for phrase/identifier matching and coverage. Common
    // question words must not independently retrieve unrelated entities.
    var matchingTerms: [NormalizedSearchTerm] {
        normalizedText.terms.filter { !isStopWord($0) }
    }

    func isStopWord(_ term: NormalizedSearchTerm) -> Bool {
        isMultiword && Self.stopWords.contains(term.alternatives[0])
    }

    private static let stopWords = Set([
        "a", "an", "are", "as", "at", "be", "by", "can", "could", "do", "does",
        "for", "from", "how", "i", "in", "is", "it", "of", "on", "or", "the",
        "to", "was", "were", "what", "when", "where", "which", "who", "why", "with",
        "а", "в", "во", "для", "и", "из", "как", "какие", "какой", "когда",
        "кто", "ли", "на", "о", "об", "от", "по", "почему", "с", "со",
        "такое", "у", "что", "это",
    ].map(SearchTextNormalizer.normalizeIdentifier))

    /// Long, unbroken input is much more likely to be an address or another
    /// identifier than human-language text. It may match an exact identifier
    /// field, but must not produce incidental word matches from small address
    /// fragments while a query source resolves it.
    public var requiresExactIdentifierMatch: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 24
            && trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}

public enum SearchTextNormalizer {
    private static let locale = Locale(identifier: "en_US_POSIX")

    public static func normalize(_ text: String) -> NormalizedSearchText {
        let canonical = normalizeWords(text)
        let canonicalTokens = canonical.split(separator: " ").map(String.init)
        let terms = canonicalTokens.map { token in
            var alternatives = [token]
            if let transliteratedToken = transliterate(token).map(normalizeWords),
               !transliteratedToken.isEmpty {
                alternatives.append(transliteratedToken)
            }
            return NormalizedSearchTerm(alternatives: unique(alternatives))
        }
        let transliterated = transliterate(canonical)
            .map(normalizeWords)
            .flatMap { $0 == canonical ? nil : $0.nilIfEmpty }

        return NormalizedSearchText(
            canonical: canonical,
            transliterated: transliterated,
            terms: terms
        )
    }

    public static func normalizeIdentifier(_ text: String) -> String {
        fold(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeWords(_ text: String) -> String {
        let folded = fold(text)
        var result = ""
        var needsSeparator = false

        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if needsSeparator, !result.isEmpty {
                    result.append(" ")
                }
                result.unicodeScalars.append(scalar)
                needsSeparator = false
            } else {
                needsSeparator = true
            }
        }
        return result
    }

    private static func fold(_ text: String) -> String {
        text
            .precomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: locale
            )
            .lowercased(with: locale)
    }

    private static func transliterate(_ text: String) -> String? {
        // ICU transliteration is comparatively expensive. The overwhelming
        // majority of token names, symbols, slugs, URLs, and addresses are
        // already ASCII and cannot gain another useful representation from it.
        guard text.unicodeScalars.contains(where: { !$0.isASCII }) else {
            return nil
        }
        return text
            .applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
