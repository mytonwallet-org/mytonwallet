import Foundation

public struct UniversalSearchRankingPolicy: Hashable, Sendable {
    public let version: String
    public let matching: UniversalSearchMatchingPolicy
    public let selectionCountCap: Int

    public init(
        version: String,
        matching: UniversalSearchMatchingPolicy = .default,
        selectionCountCap: Int = 100
    ) {
        self.version = version
        self.matching = matching
        self.selectionCountCap = max(1, selectionCountCap)
    }

    public static let initial = Self(version: "3")
}

public enum SearchRelevanceBand: Int, Hashable, Sendable, Comparable, CustomStringConvertible {
    case weak
    case term
    case phrase
    case exactIdentifier

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .weak: "weak"
        case .term: "term"
        case .phrase: "phrase"
        case .exactIdentifier: "identifier"
        }
    }
}

public enum SearchTrustTier: Int, Hashable, Sendable, Comparable, CustomStringConvertible {
    case unknown
    case established
    case curated
    case verified

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .unknown: "unknown"
        case .established: "established"
        case .curated: "curated"
        case .verified: "verified"
        }
    }
}

public struct SearchRankKey: Hashable, Sendable, Comparable {
    public let relevanceBand: SearchRelevanceBand
    public let matchKind: SearchMatchKind
    public let matchedTermCount: Int
    public let totalTermCount: Int
    public let fieldPriority: Int
    public let hasInteraction: Bool
    public let selectionCount: Int
    public let lastSelectedAt: Date?
    public let personalPriority: Int
    public let trustTier: SearchTrustTier
    public let baseCurrencyValue: Double
    public let recommendationFreshness: SearchSignalFreshness
    public let recommendationValue: Double
    public let popularityFreshness: SearchSignalFreshness
    public let popularityValue: Double
    public let categoryPriority: Int

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.relevanceBand != rhs.relevanceBand {
            return lhs.relevanceBand < rhs.relevanceBand
        }

        let lhsCoverage = lhs.matchedTermCount * max(1, rhs.totalTermCount)
        let rhsCoverage = rhs.matchedTermCount * max(1, lhs.totalTermCount)
        if lhsCoverage != rhsCoverage {
            return lhsCoverage < rhsCoverage
        }
        if lhs.personalPriority != rhs.personalPriority {
            return lhs.personalPriority < rhs.personalPriority
        }
        if lhs.hasInteraction != rhs.hasInteraction {
            return !lhs.hasInteraction && rhs.hasInteraction
        }
        if lhs.selectionCount != rhs.selectionCount {
            return lhs.selectionCount < rhs.selectionCount
        }
        if lhs.lastSelectedAt != rhs.lastSelectedAt {
            return (lhs.lastSelectedAt ?? .distantPast) < (rhs.lastSelectedAt ?? .distantPast)
        }
        if lhs.baseCurrencyValue != rhs.baseCurrencyValue {
            return lhs.baseCurrencyValue < rhs.baseCurrencyValue
        }
        if lhs.trustTier != rhs.trustTier {
            return lhs.trustTier < rhs.trustTier
        }
        if lhs.matchKind != rhs.matchKind {
            return lhs.matchKind < rhs.matchKind
        }
        if lhs.fieldPriority != rhs.fieldPriority {
            return lhs.fieldPriority < rhs.fieldPriority
        }
        if lhs.recommendationFreshness != rhs.recommendationFreshness {
            return lhs.recommendationFreshness.rawValue < rhs.recommendationFreshness.rawValue
        }
        if lhs.recommendationValue != rhs.recommendationValue {
            return lhs.recommendationValue < rhs.recommendationValue
        }
        if lhs.popularityFreshness != rhs.popularityFreshness {
            return lhs.popularityFreshness.rawValue < rhs.popularityFreshness.rawValue
        }
        if lhs.popularityValue != rhs.popularityValue {
            return lhs.popularityValue < rhs.popularityValue
        }
        return lhs.categoryPriority < rhs.categoryPriority
    }
}

public struct UniversalSearchHit: Hashable, Sendable, Identifiable {
    public var id: SearchEntityID { document.id }

    public let document: SearchDocument
    public let match: SearchMatch
    public let rank: SearchRankKey
    public let rankingExplanation: [String]

    public init(
        document: SearchDocument,
        match: SearchMatch,
        rank: SearchRankKey,
        rankingExplanation: [String]
    ) {
        self.document = document
        self.match = match
        self.rank = rank
        self.rankingExplanation = rankingExplanation
    }
}

public struct UniversalSearchEngine: Sendable {
    public let policy: UniversalSearchRankingPolicy
    private let matcher: UniversalSearchMatcher

    public init(policy: UniversalSearchRankingPolicy = .initial) {
        self.policy = policy
        self.matcher = UniversalSearchMatcher(policy: policy.matching)
    }

    public func search(
        _ query: UniversalSearchQuery,
        in documents: [SearchDocument],
        now: Date = Date()
    ) -> [UniversalSearchHit] {
        search(query, in: UniversalSearchIndex(documents: documents), now: now)
    }

    public func search(
        _ query: UniversalSearchQuery,
        in index: UniversalSearchIndex,
        now: Date = Date()
    ) -> [UniversalSearchHit] {
        guard !query.isEmpty else { return [] }

        let candidateEntries = index.candidateEntries(for: query)
        var bestHitByID = matches(
            query,
            in: candidateEntries,
            now: now
        )

        // A single edit can alter the leading gram (for example, `xallet`).
        // Preserve typo recovery by scanning the full corpus only when the
        // indexed fast path produced no result at all.
        if bestHitByID.isEmpty,
           !query.requiresExactIdentifierMatch,
           query.normalizedText.terms.contains(where: {
               $0.alternatives.contains(where: { $0.count >= policy.matching.minimumFuzzyLength })
           }) {
            bestHitByID = matches(query, in: index.entries, now: now)
        }

        return bestHitByID.values.sorted(by: outranks)
    }

    private func matches(
        _ query: UniversalSearchQuery,
        in entries: [IndexedSearchDocument],
        now: Date
    ) -> [SearchEntityID: UniversalSearchHit] {
        var bestHitByID: [SearchEntityID: UniversalSearchHit] = [:]
        for entry in entries {
            guard !Task.isCancelled else { return [:] }
            let document = entry.document
            guard let match = matcher.match(entry, query: query) else { continue }
            let hit = makeHit(document: document, match: match, now: now)
            if let previous = bestHitByID[document.id] {
                if outranks(hit, previous) {
                    bestHitByID[document.id] = hit
                }
            } else {
                bestHitByID[document.id] = hit
            }
        }
        return bestHitByID
    }

    public func search(
        _ text: String,
        in documents: [SearchDocument],
        now: Date = Date()
    ) -> [UniversalSearchHit] {
        search(UniversalSearchQuery(text), in: documents, now: now)
    }

    public func search(
        _ text: String,
        in index: UniversalSearchIndex,
        now: Date = Date()
    ) -> [UniversalSearchHit] {
        search(UniversalSearchQuery(text), in: index, now: now)
    }

    public func topHit(
        for query: UniversalSearchQuery,
        in documents: [SearchDocument],
        now: Date = Date()
    ) -> UniversalSearchHit? {
        search(query, in: documents, now: now).first
    }

    private func makeHit(
        document: SearchDocument,
        match: SearchMatch,
        now: Date
    ) -> UniversalSearchHit {
        let interaction = document.signals.interaction
        let recommendation = rankedValue(document.signals.recommendation, at: now)
        let popularity = rankedValue(document.signals.popularity, at: now)
        let baseCurrencyValue = finiteNonnegative(document.signals.baseCurrencyValue)
        let rank = SearchRankKey(
            relevanceBand: relevanceBand(for: match),
            matchKind: match.kind,
            matchedTermCount: match.matchedTermCount,
            totalTermCount: match.totalTermCount,
            fieldPriority: match.fieldKind.rankingPriority,
            hasInteraction: interaction.map { $0.selectionCount > 0 } ?? false,
            selectionCount: min(interaction?.selectionCount ?? 0, policy.selectionCountCap),
            lastSelectedAt: interaction?.lastSelectedAt,
            personalPriority: personalPriority(for: document),
            trustTier: trustTier(for: document),
            baseCurrencyValue: baseCurrencyValue,
            recommendationFreshness: recommendation.freshness,
            recommendationValue: recommendation.value,
            popularityFreshness: popularity.freshness,
            popularityValue: popularity.value,
            categoryPriority: categoryPriority(for: document)
        )
        return UniversalSearchHit(
            document: document,
            match: match,
            rank: rank,
            rankingExplanation: explanation(
                document: document,
                match: match,
                rank: rank
            )
        )
    }

    private func outranks(_ lhs: UniversalSearchHit, _ rhs: UniversalSearchHit) -> Bool {
        if lhs.rank < rhs.rank { return false }
        if rhs.rank < lhs.rank { return true }
        return lhs.id < rhs.id
    }

    private func relevanceBand(for match: SearchMatch) -> SearchRelevanceBand {
        if match.kind == .exactIdentifier {
            return .exactIdentifier
        }
        if [.keyword, .description].contains(match.fieldKind) {
            return .weak
        }
        switch match.kind {
        case .exactPhrase, .phrasePrefix:
            return .phrase
        case .exactWord, .wordPrefix:
            return .term
        case .substring, .fuzzy:
            return .weak
        case .exactIdentifier:
            return .exactIdentifier
        }
    }

    private func personalPriority(for document: SearchDocument) -> Int {
        let traits = document.signals.traits
        // Product priorities apply within comparable text relevance; exact identifiers still win.
        switch document.kind {
        case .wallet where traits.contains(.external):
            return 1600
        case .application where traits.contains(.connected):
            return 1500
        case .token where traits.contains(.held), .stock where traits.contains(.held):
            return 1400
        case .token where traits.contains(.tracked), .stock where traits.contains(.tracked):
            return 1300
        case .collectible:
            return 1200
        case .collection:
            return 1100
        case .wallet:
            return traits.contains(.viewOnly) ? 900 : 1000
        case .walletAction:
            return 800
        case .setting:
            return 700
        case .token where !traits.intersection([.popular, .trending, .curated]).isEmpty,
             .stock where !traits.intersection([.popular, .trending, .curated]).isEmpty:
            return 600
        case .application:
            return 500
        case .site:
            return 400
        case .webSearchHistory:
            return 300
        case .agentChat:
            return 200
        case .agentAction:
            return 100
        default:
            return 0
        }
    }

    private func trustTier(for document: SearchDocument) -> SearchTrustTier {
        let traits = document.signals.traits
        if traits.contains(.verified) {
            return .verified
        }
        if traits.contains(.curated) || traits.contains(.popular) {
            return .curated
        }
        if traits.contains(.hasMarketData) {
            return .established
        }
        return .unknown
    }

    private func categoryPriority(for document: SearchDocument) -> Int {
        let traits = document.signals.traits
        switch document.kind {
        case .wallet:
            return 700
        case .walletAction:
            return 450
        case .setting:
            return 425
        case .collectible:
            return 650
        case .collection:
            return 600
        case .agentChat:
            return 550
        case .token, .stock:
            return 500
        case .application:
            return 400
        case .site where traits.contains(.fromHistory):
            return 300
        case .site:
            return 250
        case .webSearchHistory:
            return 200
        case .agentAction:
            return 100
        case .webSearchAction:
            return 0
        }
    }

    private func rankedValue(
        _ signal: SearchRankedSignal?,
        at date: Date
    ) -> (freshness: SearchSignalFreshness, value: Double) {
        guard let signal else { return (.unavailable, 0) }
        let freshness = signal.freshness(at: date)
        guard freshness != .unavailable else { return (.unavailable, 0) }

        if let score = signal.score, score.isFinite {
            return (freshness, min(max(score, 0), 1))
        }
        if let rank = signal.rank, rank > 0 {
            return (freshness, 1 / Double(rank))
        }
        return (freshness, 0)
    }

    private func finiteNonnegative(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return max(0, value)
    }

    private func explanation(
        document: SearchDocument,
        match: SearchMatch,
        rank: SearchRankKey
    ) -> [String] {
        var values = [
            "band=\(rank.relevanceBand)",
            "match=\(match.kind)",
            "field=\(match.fieldKind)",
            "coverage=\(match.matchedTermCount)/\(match.totalTermCount)",
            "personal=\(rank.personalPriority)",
            "trust=\(rank.trustTier)",
            "category=\(rank.categoryPriority)",
        ]
        if match.usedTransliteration {
            values.append("transliterated")
        }
        if rank.hasInteraction {
            values.append("selected=\(rank.selectionCount)")
        }
        if rank.baseCurrencyValue > 0 {
            values.append("balance=\(rank.baseCurrencyValue)")
        }
        if rank.recommendationFreshness != .unavailable,
           let source = document.signals.recommendation?.source {
            values.append("recommendation=\(source.rawValue):\(rank.recommendationValue)")
        }
        if rank.popularityFreshness != .unavailable,
           let source = document.signals.popularity?.source {
            values.append("popularity=\(source.rawValue):\(rank.popularityValue)")
        }
        return values
    }
}
