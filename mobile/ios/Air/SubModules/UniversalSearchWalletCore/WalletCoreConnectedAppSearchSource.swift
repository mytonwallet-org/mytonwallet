import Foundation
import UniversalSearchCore
import WalletCore

public struct WalletCoreConnectedAppSearchSource: UniversalSearchSource {
    public typealias Loader = @Sendable (UniversalSearchContext) async throws -> [ApiDapp]

    public static let id = SearchSourceID("wallet-core:connected-apps")

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
        self.init(loader: Self.loadLiveApps)
    }

    public func snapshot(
        for context: UniversalSearchContext
    ) async throws -> UniversalSearchSourceSnapshot {
        let apps = try await loader(context)
        return UniversalSearchSourceSnapshot(
            sourceID: sourceID,
            authority: WalletCoreSearchSourceAuthority.local,
            generatedAt: clock(),
            documents: Self.documents(apps: apps)
        )
    }

    public static func documents(apps: [ApiDapp]) -> [SearchDocument] {
        var appByID: [String: ApiDapp] = [:]
        for app in apps {
            let id = WalletCoreApplicationIdentity.canonicalID(url: app.url)
            if let previous = appByID[id] {
                if (app.connectedAt ?? Int.min) > (previous.connectedAt ?? Int.min) {
                    appByID[id] = app
                }
            } else {
                appByID[id] = app
            }
        }

        return appByID.map { id, app in
            let host = WalletCoreApplicationIdentity.hostAlias(url: app.url)
            return SearchDocument(
                id: SearchEntityID("application:\(id)"),
                kind: .application,
                fields: makeSearchFields([
                    (app.name, .title, .text),
                    (app.url, .url, .text),
                    (host, .domain, .text),
                ]),
                attributes: makeSearchAttributes([
                    (WalletCoreSearchAttributeKey.iconURL, app.iconUrl),
                    (WalletCoreSearchAttributeKey.url, app.url),
                ]),
                signals: SearchSignals(
                    traits: [.connected],
                    interaction: app.connectedAt.flatMap { connectedAt in
                        guard connectedAt > 0 else { return nil }
                        return SearchInteractionSignal(
                            lastSelectedAt: Date(timeIntervalSince1970: Double(connectedAt) / 1_000),
                            selectionCount: 1
                        )
                    }
                )
            )
        }.sorted { $0.id < $1.id }
    }

    private static func loadLiveApps(
        context: UniversalSearchContext
    ) async throws -> [ApiDapp] {
        guard let accountID = context.scopeID else { return [] }
        return try await Api.getDapps(accountId: accountID)
    }
}
