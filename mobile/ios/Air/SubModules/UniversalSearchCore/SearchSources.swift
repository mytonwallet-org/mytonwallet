import Foundation

public struct UniversalSearchContext: Codable, Hashable, Sendable {
    public let scopeID: String?
    public let network: String?
    public let localeIdentifier: String

    public init(
        scopeID: String?,
        network: String?,
        localeIdentifier: String
    ) {
        self.scopeID = scopeID
        self.network = network
        self.localeIdentifier = localeIdentifier
    }
}

public struct SearchSignalContribution: Codable, Hashable, Sendable {
    public let entityID: SearchEntityID
    public let signals: SearchSignals

    public init(entityID: SearchEntityID, signals: SearchSignals) {
        self.entityID = entityID
        self.signals = signals
    }
}

/// A provider's complete current contribution, not a delta.
///
/// A source may contribute authoritative documents, signals for documents owned
/// by another source, or both. Replacing snapshots makes removal and feed expiry
/// deterministic and avoids signals lingering after a refresh.
public struct UniversalSearchSourceSnapshot: Codable, Hashable, Sendable {
    public let sourceID: SearchSourceID
    public let authority: Int
    public let revision: String?
    public let generatedAt: Date
    public let expiresAt: Date?
    public let staleUntil: Date?
    public let documents: [SearchDocument]
    public let signalContributions: [SearchSignalContribution]

    public init(
        sourceID: SearchSourceID,
        authority: Int = 0,
        revision: String? = nil,
        generatedAt: Date,
        expiresAt: Date? = nil,
        staleUntil: Date? = nil,
        documents: [SearchDocument] = [],
        signalContributions: [SearchSignalContribution] = []
    ) {
        self.sourceID = sourceID
        self.authority = authority
        self.revision = revision
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
        self.staleUntil = staleUntil
        self.documents = documents
        self.signalContributions = signalContributions
    }

    public func isUsable(at date: Date) -> Bool {
        guard let expiresAt, date > expiresAt else { return true }
        return staleUntil.map { date <= $0 } ?? false
    }
}

/// The context fields a source's snapshot depends on.
///
/// A snapshot stays valid while those fields are unchanged, so an account switch keeps every
/// snapshot that the new account shares instead of discarding it.
public enum UniversalSearchSourceScoping: Hashable, Sendable {
    /// Depends only on the locale
    case global
    /// Depends on the network and locale
    case network
    /// Depends on the account, network, and locale
    case account

    public func scopeKey(for context: UniversalSearchContext) -> String {
        switch self {
        case .global:
            "locale=\(context.localeIdentifier)"
        case .network:
            "locale=\(context.localeIdentifier)|network=\(context.network ?? "")"
        case .account:
            "locale=\(context.localeIdentifier)|network=\(context.network ?? "")|scope=\(context.scopeID ?? "")"
        }
    }
}

public protocol UniversalSearchSource: Sendable {
    var sourceID: SearchSourceID { get }
    var scoping: UniversalSearchSourceScoping { get }

    func snapshot(for context: UniversalSearchContext) async throws -> UniversalSearchSourceSnapshot
}

extension UniversalSearchSource {
    public var scoping: UniversalSearchSourceScoping { .account }
}

/// Produces query-scoped snapshots that augment the persistent local corpus.
///
/// A query source may perform network work and emit multiple complete snapshots
/// as results arrive. Consumers replace the preceding snapshot from the same
/// source, cancel the stream when the query changes, and remove its contribution
/// before starting a different query.
public protocol UniversalSearchQuerySource: Sendable {
    var sourceID: SearchSourceID { get }

    func snapshots(
        for query: UniversalSearchQuery,
        context: UniversalSearchContext
    ) -> AsyncThrowingStream<UniversalSearchSourceSnapshot, Error>
}

/// Replaces complete source snapshots and produces one deduplicated search corpus.
///
/// The highest-authority source owns an entity's searchable fields. Signals from
/// every live source are merged independently, so recommendation feeds can enrich
/// local documents without replacing trusted display or routing data.
public struct UniversalSearchCorpus: Sendable {
    public private(set) var snapshots: [SearchSourceID: UniversalSearchSourceSnapshot]

    public init(snapshots: [UniversalSearchSourceSnapshot] = []) {
        self.snapshots = Dictionary(
            snapshots.map { ($0.sourceID, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    public mutating func replace(_ snapshot: UniversalSearchSourceSnapshot) {
        snapshots[snapshot.sourceID] = snapshot
    }

    public mutating func remove(sourceID: SearchSourceID) {
        snapshots[sourceID] = nil
    }

    public func documents(at date: Date = Date()) -> [SearchDocument] {
        let usableSnapshots = snapshots.values
            .filter { $0.isUsable(at: date) }
            .sorted(by: snapshotPrecedes)

        var authoritativeDocuments: [SearchEntityID: SearchDocument] = [:]
        var signalCandidates: [SearchEntityID: [SignalCandidate]] = [:]

        for snapshot in usableSnapshots {
            for document in snapshot.documents {
                if authoritativeDocuments[document.id] == nil {
                    authoritativeDocuments[document.id] = document
                }
                signalCandidates[document.id, default: []].append(
                    SignalCandidate(
                        authority: snapshot.authority,
                        sourceID: snapshot.sourceID,
                        precedenceWithinSource: 1,
                        signals: document.signals
                    )
                )
            }
            for contribution in snapshot.signalContributions {
                signalCandidates[contribution.entityID, default: []].append(
                    SignalCandidate(
                        authority: snapshot.authority,
                        sourceID: snapshot.sourceID,
                        precedenceWithinSource: 0,
                        signals: contribution.signals
                    )
                )
            }
        }

        return authoritativeDocuments.values.map { document in
            var document = document
            document.signals = mergedSignals(signalCandidates[document.id] ?? [])
            return document
        }.sorted { $0.id < $1.id }
    }

    /// The corpus projection stays stable through this instant. Snapshots are
    /// still usable at their expiration boundary, so callers should rebuild
    /// only after the returned date has passed.
    public func nextUsabilityBoundary(after date: Date) -> Date? {
        snapshots.values.compactMap { snapshot in
            guard let expiresAt = snapshot.expiresAt else { return nil }
            let boundary = max(expiresAt, snapshot.staleUntil ?? expiresAt)
            return boundary >= date ? boundary : nil
        }.min()
    }

    private func snapshotPrecedes(
        _ lhs: UniversalSearchSourceSnapshot,
        _ rhs: UniversalSearchSourceSnapshot
    ) -> Bool {
        if lhs.authority != rhs.authority {
            return lhs.authority > rhs.authority
        }
        return lhs.sourceID < rhs.sourceID
    }

    private func mergedSignals(_ candidates: [SignalCandidate]) -> SearchSignals {
        let ordered = candidates.sorted()
        var result = SearchSignals()
        for candidate in ordered {
            let signals = candidate.signals
            result.traits.formUnion(signals.traits)
            result.baseCurrencyValue = result.baseCurrencyValue ?? signals.baseCurrencyValue
            if let interaction = signals.interaction {
                // Connection and selection history can describe overlapping usage.
                result.interaction = SearchInteractionSignal(
                    lastSelectedAt: max(result.interaction?.lastSelectedAt ?? .distantPast, interaction.lastSelectedAt),
                    selectionCount: max(result.interaction?.selectionCount ?? 0, interaction.selectionCount)
                )
            }
            result.popularity = result.popularity ?? signals.popularity
            result.recommendation = result.recommendation ?? signals.recommendation
        }
        return result
    }
}

private struct SignalCandidate: Comparable {
    let authority: Int
    let sourceID: SearchSourceID
    let precedenceWithinSource: Int
    let signals: SearchSignals

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.authority != rhs.authority {
            return lhs.authority > rhs.authority
        }
        if lhs.sourceID != rhs.sourceID {
            return lhs.sourceID < rhs.sourceID
        }
        return lhs.precedenceWithinSource < rhs.precedenceWithinSource
    }
}
