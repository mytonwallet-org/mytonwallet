@testable import UniversalSearchCore

func makeSearchHit(_ document: SearchDocument) -> UniversalSearchHit {
    UniversalSearchHit(
        document: document,
        match: SearchMatch(
            kind: .exactPhrase,
            fieldKind: .title,
            matchedTermCount: 1,
            totalTermCount: 1,
            usedTransliteration: false,
            matchedValue: document.fields.first?.value ?? ""
        ),
        rank: SearchRankKey(
            relevanceBand: .phrase,
            matchKind: .exactPhrase,
            matchedTermCount: 1,
            totalTermCount: 1,
            fieldPriority: 0,
            hasInteraction: false,
            selectionCount: 0,
            lastSelectedAt: nil,
            personalPriority: 0,
            trustTier: .unknown,
            baseCurrencyValue: 0,
            recommendationFreshness: .unavailable,
            recommendationValue: 0,
            popularityFreshness: .unavailable,
            popularityValue: 0,
            categoryPriority: 0
        ),
        rankingExplanation: []
    )
}
