import Foundation

public struct SearchEntityID: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum SearchEntityKind: String, CaseIterable, Codable, Hashable, Sendable {
    case agentChat
    case agentAction
    case token
    case stock
    case collectible
    case collection
    case application
    case wallet
    case walletAction
    case setting
    case site
    case webSearchHistory
    case webSearchAction
}

public enum SearchFieldKind: String, CaseIterable, Codable, Hashable, Sendable {
    case identifier
    case address
    case domain
    case symbol
    case title
    case alias
    case url
    case keyword
    case description

    public var rankingPriority: Int {
        switch self {
        case .identifier: 900
        case .address: 850
        case .domain: 800
        // Exact names and exact tickers are equally strong. Ownership,
        // interaction, and balance signals then break ties, preventing an
        // unrelated token that copied a well-known name into its symbol from
        // outranking the held native asset.
        case .symbol, .title: 700
        case .alias: 500
        case .url: 400
        case .keyword: 300
        case .description: 100
        }
    }
}

public enum SearchFieldMatchPolicy: String, Codable, Hashable, Sendable {
    case text
    case exact
}

public struct SearchField: Codable, Hashable, Sendable {
    public let value: String
    public let kind: SearchFieldKind
    public let matchPolicy: SearchFieldMatchPolicy

    public init(
        _ value: String,
        kind: SearchFieldKind,
        matchPolicy: SearchFieldMatchPolicy = .text
    ) {
        self.value = value
        self.kind = kind
        self.matchPolicy = matchPolicy
    }
}

public enum SearchDocumentMatchRequirement: String, Codable, Hashable, Sendable {
    case anyTerm
    case exactIdentifier
}

public struct SearchTraits: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let owned = Self(rawValue: 1 << 0)
    public static let held = Self(rawValue: 1 << 1)
    public static let tracked = Self(rawValue: 1 << 2)
    public static let connected = Self(rawValue: 1 << 3)
    public static let viewOnly = Self(rawValue: 1 << 4)
    public static let external = Self(rawValue: 1 << 5)
    public static let fromHistory = Self(rawValue: 1 << 6)
    public static let popular = Self(rawValue: 1 << 7)
    public static let trending = Self(rawValue: 1 << 8)
    public static let curated = Self(rawValue: 1 << 9)
    public static let verified = Self(rawValue: 1 << 10)
    public static let hasMarketData = Self(rawValue: 1 << 11)
}

public struct SearchInteractionSignal: Codable, Hashable, Sendable {
    public let lastSelectedAt: Date
    public let selectionCount: Int

    public init(lastSelectedAt: Date, selectionCount: Int) {
        self.lastSelectedAt = lastSelectedAt
        self.selectionCount = max(0, selectionCount)
    }
}

public struct SearchSourceID: RawRepresentable, Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum SearchSignalFreshness: Int, Codable, Hashable, Sendable {
    case unavailable
    case stale
    case fresh
}

/// A normalized rank supplied by a catalog, recommendation, or popularity source.
///
/// `score` is expected to be in `0...1`. If a source only has an ordered feed, it
/// can provide `rank` and the search engine derives a bounded value from it.
public struct SearchRankedSignal: Codable, Hashable, Sendable {
    public let source: SearchSourceID
    public let rank: Int?
    public let score: Double?
    public let generatedAt: Date?
    public let expiresAt: Date?
    public let staleUntil: Date?
    public let modelVersion: String?
    public let reason: String?

    public init(
        source: SearchSourceID,
        rank: Int? = nil,
        score: Double? = nil,
        generatedAt: Date? = nil,
        expiresAt: Date? = nil,
        staleUntil: Date? = nil,
        modelVersion: String? = nil,
        reason: String? = nil
    ) {
        self.source = source
        self.rank = rank
        self.score = score
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.staleUntil = staleUntil
        self.modelVersion = modelVersion
        self.reason = reason
    }

    public func freshness(at date: Date) -> SearchSignalFreshness {
        guard let expiresAt else { return .fresh }
        guard date > expiresAt else { return .fresh }
        guard let staleUntil, date <= staleUntil else { return .unavailable }
        return .stale
    }
}

public struct SearchSignals: Codable, Hashable, Sendable {
    public var traits: SearchTraits
    public var baseCurrencyValue: Double?
    public var interaction: SearchInteractionSignal?
    public var popularity: SearchRankedSignal?
    public var recommendation: SearchRankedSignal?

    public init(
        traits: SearchTraits = [],
        baseCurrencyValue: Double? = nil,
        interaction: SearchInteractionSignal? = nil,
        popularity: SearchRankedSignal? = nil,
        recommendation: SearchRankedSignal? = nil
    ) {
        self.traits = traits
        self.baseCurrencyValue = baseCurrencyValue
        self.interaction = interaction
        self.popularity = popularity
        self.recommendation = recommendation
    }
}

public struct SearchAttributeKey: RawRepresentable, Codable, Hashable, Sendable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SearchAttribute: Codable, Hashable, Sendable {
    public let key: SearchAttributeKey
    public let value: String

    public init(key: SearchAttributeKey, value: String) {
        self.key = key
        self.value = value
    }
}

public struct SearchDocument: Codable, Hashable, Sendable, Identifiable {
    public let id: SearchEntityID
    public let kind: SearchEntityKind
    public let fields: [SearchField]
    public let matchRequirement: SearchDocumentMatchRequirement
    public let attributes: [SearchAttribute]
    public var signals: SearchSignals

    public init(
        id: SearchEntityID,
        kind: SearchEntityKind,
        fields: [SearchField],
        matchRequirement: SearchDocumentMatchRequirement = .anyTerm,
        attributes: [SearchAttribute] = [],
        signals: SearchSignals = .init()
    ) {
        self.id = id
        self.kind = kind
        self.fields = fields
        self.matchRequirement = matchRequirement
        self.attributes = attributes
        self.signals = signals
    }

    public func attributeValue(for key: SearchAttributeKey) -> String? {
        attributes.first { $0.key == key }?.value
    }
}
