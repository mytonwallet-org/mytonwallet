import Foundation
import UniversalSearchCore
import WalletCore

/// The part of a futures market that search matches on. Prices, volumes and charts are left out: they change
/// with every catalogue push, and rows read them from `PerpsStore` when they are shown.
public struct WalletCoreFuturesSearchEntry: Hashable, Sendable {
    public let assetID: String
    public let symbol: String
    public let displayName: String?
    public let label: String?
    public let keywords: [String]

    public init(assetID: String, symbol: String, displayName: String?, label: String?, keywords: [String]) {
        self.assetID = assetID
        self.symbol = symbol
        self.displayName = displayName
        self.label = label
        self.keywords = keywords
    }

    public init(_ asset: ApiPerpsAsset) {
        self.init(
            assetID: asset.id,
            symbol: asset.symbol,
            displayName: asset.displayName,
            label: asset.label,
            keywords: asset.keywords ?? []
        )
    }
}

/// The futures catalogue, shared by every account. Which accounts can open a market is decided when a result is
/// shown, so switching accounts never re-reads or re-indexes the catalogue.
public struct WalletCoreFuturesSearchSource: UniversalSearchSource {
    public typealias Loader = @Sendable () async -> [WalletCoreFuturesSearchEntry]

    public static let id = SearchSourceID("wallet-core:futures")

    public let sourceID = Self.id
    public var scoping: UniversalSearchSourceScoping { .global }
    private let loader: Loader
    private let clock: @Sendable () -> Date

    public init(
        loader: @escaping Loader,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.loader = loader
        self.clock = clock
    }

    public init() {
        self.init(loader: {
            await MainActor.run { WalletCoreFuturesSearchSource.entries(market: PerpsStore.shared.market) }
        })
    }

    public static func entityID(assetID: String) -> SearchEntityID {
        SearchEntityID("futures:\(assetID)")
    }

    public static func entries(market: ApiPerpsMarketSnapshot?) -> [WalletCoreFuturesSearchEntry] {
        (market?.assets ?? []).map(WalletCoreFuturesSearchEntry.init)
    }

    public static func documents(entries: [WalletCoreFuturesSearchEntry]) -> [SearchDocument] {
        var seenAssetIDs = Set<String>()
        return entries
            .filter { seenAssetIDs.insert($0.assetID).inserted }
            .map { entry in
                var fields: [(String?, SearchFieldKind, SearchFieldMatchPolicy)] = [
                    (entry.displayName, .title, .text),
                    (entry.symbol, .symbol, .text),
                    (entry.label, .alias, .text),
                ]
                fields += entry.keywords.map { ($0, .keyword, .text) }
                return SearchDocument(
                    id: entityID(assetID: entry.assetID),
                    kind: .futuresMarket,
                    fields: makeSearchFields(fields),
                    attributes: makeSearchAttributes([
                        (WalletCoreSearchAttributeKey.futuresAssetID, entry.assetID),
                    ])
                )
            }
            .sorted { $0.id < $1.id }
    }

    public func snapshot(for context: UniversalSearchContext) async throws -> UniversalSearchSourceSnapshot {
        UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            authority: WalletCoreSearchSourceAuthority.local,
            generatedAt: clock(),
            documents: Self.documents(entries: await loader())
        )
    }
}

/// Marks the markets the account holds a position in. Only opening or closing a position changes it; the
/// position's value and profit are read when a row is shown.
public struct WalletCoreFuturesPositionSearchSource: UniversalSearchSource {
    public typealias Loader = @Sendable (_ accountID: String) async -> Set<String>

    public static let id = SearchSourceID("wallet-core:futures-positions")

    public let sourceID = Self.id
    private let loader: Loader
    private let clock: @Sendable () -> Date

    public init(
        loader: @escaping Loader,
        clock: @escaping @Sendable () -> Date = Date.init
    ) {
        self.loader = loader
        self.clock = clock
    }

    public init() {
        self.init(loader: { accountID in
            await MainActor.run { WalletCoreFuturesPositionSearchSource.heldAssetIDs(PerpsStore.shared.snapshots[accountID]) }
        })
    }

    public static func heldAssetIDs(_ snapshot: ApiPerpsAccountSnapshot?) -> Set<String> {
        Set(snapshot?.positions.map(\.assetId) ?? [])
    }

    public func snapshot(for context: UniversalSearchContext) async throws -> UniversalSearchSourceSnapshot {
        let assetIDs = if let accountID = context.scopeID { await loader(accountID) } else { Set<String>() }
        return UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            authority: WalletCoreSearchSourceAuthority.local,
            generatedAt: clock(),
            signalContributions: assetIDs.sorted().map {
                SearchSignalContribution(
                    entityID: WalletCoreFuturesSearchSource.entityID(assetID: $0),
                    signals: SearchSignals(traits: .held)
                )
            }
        )
    }
}
