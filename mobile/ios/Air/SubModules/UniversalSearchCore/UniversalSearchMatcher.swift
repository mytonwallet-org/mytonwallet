import Foundation

public enum SearchMatchKind: Int, Hashable, Sendable, Comparable {
    case fuzzy = 100
    case substring = 200
    case wordPrefix = 300
    case exactWord = 400
    case phrasePrefix = 500
    case exactPhrase = 600
    case exactIdentifier = 700

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SearchMatch: Hashable, Sendable {
    public let kind: SearchMatchKind
    public let fieldKind: SearchFieldKind
    public let matchedTermCount: Int
    public let totalTermCount: Int
    /// Query terms matched as whole words or word prefixes, including metadata qualifiers.
    public let wordMatchCount: Int
    public let usedTransliteration: Bool
    public let matchedValue: String

    public var coverage: Double {
        guard totalTermCount > 0 else { return 0 }
        return Double(matchedTermCount) / Double(totalTermCount)
    }

    public init(
        kind: SearchMatchKind,
        fieldKind: SearchFieldKind,
        matchedTermCount: Int,
        totalTermCount: Int,
        wordMatchCount: Int? = nil,
        usedTransliteration: Bool,
        matchedValue: String
    ) {
        self.kind = kind
        self.fieldKind = fieldKind
        self.matchedTermCount = matchedTermCount
        self.totalTermCount = totalTermCount
        self.wordMatchCount = wordMatchCount ?? (kind >= .wordPrefix ? matchedTermCount : 0)
        self.usedTransliteration = usedTransliteration
        self.matchedValue = matchedValue
    }
}

public struct UniversalSearchMatchingPolicy: Hashable, Sendable {
    public let minimumPrefixLength: Int
    public let minimumSubstringLength: Int
    public let minimumFuzzyLength: Int
    public let maximumEditDistance: Int

    public init(
        minimumPrefixLength: Int = 1,
        minimumSubstringLength: Int = 2,
        minimumFuzzyLength: Int = 4,
        maximumEditDistance: Int = 1
    ) {
        self.minimumPrefixLength = max(1, minimumPrefixLength)
        self.minimumSubstringLength = max(1, minimumSubstringLength)
        self.minimumFuzzyLength = max(1, minimumFuzzyLength)
        self.maximumEditDistance = max(0, maximumEditDistance)
    }

    public static let `default` = Self()
}

public struct UniversalSearchMatcher: Sendable {
    public let policy: UniversalSearchMatchingPolicy

    public init(policy: UniversalSearchMatchingPolicy = .default) {
        self.policy = policy
    }

    public func match(
        _ document: SearchDocument,
        query: UniversalSearchQuery
    ) -> SearchMatch? {
        match(IndexedSearchDocument(document), query: query)
    }

    func match(
        _ indexedDocument: IndexedSearchDocument,
        query: UniversalSearchQuery
    ) -> SearchMatch? {
        guard !query.isEmpty else { return nil }

        let document = indexedDocument.document
        let preparedFields = indexedDocument.fields

        if let exactIdentifier = bestExactIdentifier(in: preparedFields, query: query) {
            return exactIdentifier.searchMatch(
                matchedTermCount: query.termCount,
                totalTermCount: query.termCount
            )
        }

        guard !query.requiresExactIdentifierMatch else { return nil }
        guard document.matchRequirement != .exactIdentifier else { return nil }

        let phraseMatch = bestPhraseMatch(in: preparedFields, query: query)
        if let phraseMatch, phraseMatch.relevanceBand >= .phrase {
            return phraseMatch.searchMatch(
                matchedTermCount: query.termCount,
                totalTermCount: query.termCount
            )
        }

        var termMatches: [MatchCandidate] = []
        var wordMatchCount = 0
        var hasMeaningfulMatch = false
        for term in query.normalizedText.terms {
            let isStopWord = query.isStopWord(term)
            guard let match = bestMatch(
                for: term, in: preparedFields, requiresExactWord: isStopWord
            ) else { continue }
            termMatches.append(match.candidate)
            if match.hasWordMatch { wordMatchCount += 1 }
            hasMeaningfulMatch = hasMeaningfulMatch || !isStopWord
        }
        let strongest = hasMeaningfulMatch ? termMatches.max() : nil
        // Metadata phrases must not mask stronger name/symbol matches on this entity.
        if let phraseMatch, strongest.map({ $0 < phraseMatch }) ?? true {
            return phraseMatch.searchMatch(
                matchedTermCount: query.termCount,
                totalTermCount: query.termCount
            )
        }
        guard let strongest else { return nil }

        return strongest.searchMatch(
            matchedTermCount: termMatches.count,
            totalTermCount: query.termCount,
            wordMatchCount: wordMatchCount
        )
    }

    private func bestExactIdentifier(
        in fields: [PreparedSearchField],
        query: UniversalSearchQuery
    ) -> MatchCandidate? {
        fields
            .filter { field in
                field.field.matchPolicy == .exact
                    || [.identifier, .address, .domain].contains(field.field.kind)
            }
            .filter { $0.normalizedIdentifier == query.normalizedIdentifier }
            .map {
                MatchCandidate(
                    kind: .exactIdentifier,
                    fieldKind: $0.field.kind,
                    usedTransliteration: false,
                    matchedValue: $0.field.value
                )
            }
            .max()
    }

    private func bestPhraseMatch(
        in fields: [PreparedSearchField],
        query: UniversalSearchQuery
    ) -> MatchCandidate? {
        var candidates: [MatchCandidate] = []

        for field in fields where field.field.matchPolicy == .text {
            for (queryIndex, queryPhrase) in query.normalizedText.phraseAlternatives.enumerated() {
                for (fieldIndex, fieldPhrase) in field.normalizedText.phraseAlternatives.enumerated() {
                    let kind: SearchMatchKind?
                    if fieldPhrase == queryPhrase {
                        kind = .exactPhrase
                    } else if queryPhrase.count >= policy.minimumPrefixLength,
                              fieldPhrase.hasPrefix(queryPhrase) {
                        kind = .phrasePrefix
                    } else {
                        kind = nil
                    }
                    if let kind {
                        candidates.append(MatchCandidate(
                            kind: kind,
                            fieldKind: field.field.kind,
                            usedTransliteration: queryIndex > 0 || fieldIndex > 0,
                            matchedValue: field.field.value
                        ))
                    }
                }
            }
        }
        return candidates.max()
    }

    private func bestMatch(
        for queryTerm: NormalizedSearchTerm,
        in fields: [PreparedSearchField],
        requiresExactWord: Bool
    ) -> (candidate: MatchCandidate, hasWordMatch: Bool)? {
        var best: MatchCandidate?
        var hasWordMatch = false

        for field in fields where field.field.matchPolicy == .text {
            for (queryIndex, queryAlternative) in queryTerm.alternatives.enumerated() {
                for fieldTerm in field.normalizedText.terms {
                    for (fieldIndex, fieldAlternative) in fieldTerm.alternatives.enumerated() {
                        guard let kind = matchKind(
                            query: queryAlternative,
                            candidate: fieldAlternative
                        ), !requiresExactWord || kind == .exactWord else { continue }
                        hasWordMatch = hasWordMatch || kind >= .wordPrefix

                        let candidate = MatchCandidate(
                            kind: kind,
                            fieldKind: field.field.kind,
                            usedTransliteration: queryIndex > 0 || fieldIndex > 0,
                            matchedValue: field.field.value
                        )
                        if best == nil || candidate > best! {
                            best = candidate
                        }
                    }
                }
            }
        }
        return best.map { ($0, hasWordMatch) }
    }

    private func matchKind(query: String, candidate: String) -> SearchMatchKind? {
        if candidate == query {
            return .exactWord
        }
        if query.count >= policy.minimumPrefixLength, candidate.hasPrefix(query) {
            return .wordPrefix
        }
        if query.count >= policy.minimumSubstringLength, candidate.contains(query) {
            return .substring
        }
        if query.count >= policy.minimumFuzzyLength,
           candidate.count >= policy.minimumFuzzyLength,
           editDistance(query, candidate, limit: policy.maximumEditDistance) <= policy.maximumEditDistance {
            return .fuzzy
        }
        return nil
    }

    private func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard abs(left.count - right.count) <= limit else { return limit + 1 }
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = Array(repeating: 0, count: right.count + 1)
            current[0] = leftIndex + 1
            var rowMinimum = current[0]

            for (rightIndex, rightCharacter) in right.enumerated() {
                let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
                current[rightIndex + 1] = min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[rightIndex + 1])
            }
            if rowMinimum > limit {
                return limit + 1
            }
            previous = current
        }
        return previous[right.count]
    }
}

struct PreparedSearchField: Hashable, Sendable {
    let field: SearchField
    let normalizedText: NormalizedSearchText
    let normalizedIdentifier: String

    init(_ field: SearchField) {
        self.field = field
        self.normalizedText = SearchTextNormalizer.normalize(field.value)
        self.normalizedIdentifier = SearchTextNormalizer.normalizeIdentifier(field.value)
    }
}

private struct MatchCandidate: Comparable {
    let kind: SearchMatchKind
    let fieldKind: SearchFieldKind
    let usedTransliteration: Bool
    let matchedValue: String

    var relevanceBand: SearchRelevanceBand {
        SearchRelevanceBand(kind: kind, field: fieldKind)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.relevanceBand != rhs.relevanceBand {
            return lhs.relevanceBand < rhs.relevanceBand
        }
        if lhs.kind != rhs.kind {
            return lhs.kind < rhs.kind
        }
        if lhs.fieldKind.rankingPriority != rhs.fieldKind.rankingPriority {
            return lhs.fieldKind.rankingPriority < rhs.fieldKind.rankingPriority
        }
        if lhs.usedTransliteration != rhs.usedTransliteration {
            return lhs.usedTransliteration && !rhs.usedTransliteration
        }
        return lhs.matchedValue > rhs.matchedValue
    }

    func searchMatch(matchedTermCount: Int, totalTermCount: Int, wordMatchCount: Int? = nil) -> SearchMatch {
        SearchMatch(
            kind: kind,
            fieldKind: fieldKind,
            matchedTermCount: matchedTermCount,
            totalTermCount: totalTermCount,
            wordMatchCount: wordMatchCount,
            usedTransliteration: usedTransliteration,
            matchedValue: matchedValue
        )
    }
}
