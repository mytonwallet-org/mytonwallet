import Foundation
import WalletContext
import WalletCore
import WalletCoreTypes

private let tokenSpotlightLog = Log("TokenSpotlightIndexer")

@MainActor
@available(iOS 18.4, *)
final class TokenSpotlightIndexer: WalletCoreData.EventsObserver, @unchecked Sendable {
    static let shared = TokenSpotlightIndexer()

    private var isStarted = false
    private var reindexTask: Task<Void, Never>?
    private var needsUpdate = false
    private var isWalletReady = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        WalletCoreData.add(eventObserver: self)
        Task {
            do {
                try await TokenSpotlightStore.shared.resume()
            } catch {
                tokenSpotlightLog.error("failed to restore token Spotlight catalog: \(error, .public)")
            }
        }
    }

    func setWalletReady(_ isReady: Bool) {
        if isReady { start() }
        isWalletReady = isReady
        if isReady { reindexSoon() }
    }

    func stop() {
        WalletCoreData.remove(observer: self)
        isStarted = false
        isWalletReady = false
        needsUpdate = false
    }

    private func reindexSoon() {
        guard isWalletReady else { return }
        needsUpdate = true
        guard reindexTask == nil else { return }
        reindexTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            while needsUpdate, isWalletReady {
                needsUpdate = false
                await reindex()
            }
            reindexTask = nil
        }
    }

    func recordOpened(_ token: ApiToken) {
        Task {
            guard isWalletReady else { return }
            do {
                try await TokenSpotlightStore.shared.recordOpened(TokenEntity(token: token))
                reindexSoon()
            } catch {
                tokenSpotlightLog.error("failed to save recent token: \(error, .public)")
            }
        }
    }

    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged,
             .tokensChanged,
             .swapTokensChanged,
             .baseCurrencyChanged,
             .accountNameChanged,
             .accountDeleted,
             .assetsAndActivityDataUpdated,
             .hideNoCostTokensChanged:
            reindexSoon()
        case .accountsReset:
            setWalletReady(false)
            needsUpdate = false
            Task {
                do {
                    try await TokenSpotlightStore.shared.clearPersonalization()
                } catch {
                    tokenSpotlightLog.error("failed to clear token Spotlight personalization: \(error, .public)")
                }
            }
        default:
            break
        }
    }

    private func reindex() async {
        let recent = await TokenSpotlightStore.shared.recentEntities()
        guard isWalletReady else { return }
        let entries = TokenEntityProvider.entries(recent: recent)
        do {
            try await TokenSpotlightStore.shared.update(entries)
        } catch {
            tokenSpotlightLog.error("failed to index token Spotlight entities: \(String(describing: error), .public)")
        }
    }
}
