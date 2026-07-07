import CoreSpotlight
import Foundation
import WalletContext
import WalletCore
import WalletCoreTypes

private let tokenSpotlightLog = Log("TokenSpotlightIndexer")
private let tokenSpotlightIndexName = "MyTonWallet_Tokens"
private let legacyTokenSpotlightIndexName = "MyTonWallet_TokenHoldings"

@MainActor
@available(iOS 18.4, *)
final class TokenSpotlightIndexer: WalletCoreData.EventsObserver, @unchecked Sendable {
    static let shared = TokenSpotlightIndexer()

    private var isStarted = false
    private var reindexTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        WalletCoreData.add(eventObserver: self)
    }

    func reindexSoon() {
        reindexTask?.cancel()
        reindexTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await reindex()
        }
    }

    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged,
             .tokensChanged,
             .baseCurrencyChanged,
             .accountChanged,
             .accountNameChanged,
             .accountDeleted,
             .accountsReset,
             .assetsAndActivityDataUpdated,
             .hideNoCostTokensChanged:
            reindexSoon()
        default:
            break
        }
    }

    private func reindex() async {
        let index = CSSearchableIndex(name: tokenSpotlightIndexName)

        let entities = TokenEntityProvider.suggestedEntities()
        guard !entities.isEmpty else { return }

        do {
            try await index.indexAppEntities(entities, priority: 5)
        } catch {
            tokenSpotlightLog.error("failed to index token Spotlight entities: \(String(describing: error), .public)")
        }
    }
}
